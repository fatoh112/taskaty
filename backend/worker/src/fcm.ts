import { ApiError, base64Url, decodeBase64, nowIso } from "./http.ts";
import { decryptDeviceToken } from "./notifications.ts";
import type { D1Database, D1PreparedStatement, Env } from "./types.ts";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
// A full tick uses at most 16 D1 calls and 31 FCM/OAuth fetches (2 devices × 15 users + token grant).
// This leaves headroom below the Workers Free 50-subrequest limit for runtime changes.
const MAX_DELIVERY_RECIPIENTS = 15;
const MAX_DEVICES_PER_RECIPIENT = 2;
const MAX_ATTEMPTS = 8;

function toBufferSource(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}
interface CachedAccessToken { projectId: string; value: string; expiresAt: number }
interface OutboxRow { id: string; notification_id: string; recipient_user_id: string; task_id: string | null; attempts: number }
interface DeviceRow { token_hash: string; token_ciphertext: string; token_iv: string }
interface DeliveryQueryRow extends OutboxRow {
  title: string | null;
  body: string | null;
  type: string | null;
  token_hash: string | null;
  token_ciphertext: string | null;
  token_iv: string | null;
}
interface Delivery { outbox: OutboxRow; title: string | null; body: string | null; type: string | null; devices: DeviceRow[] }
let accessTokenCache: CachedAccessToken | null = null;
let accessTokenPromise: Promise<CachedAccessToken> | null = null;

function parseServiceAccount(json?: string, projectId?: string): ServiceAccount {
  if (!json || !projectId) throw new ApiError("FCM_NOT_CONFIGURED", 503);
  try {
    const account = JSON.parse(json) as Partial<ServiceAccount>;
    if (!account.project_id || account.project_id !== projectId || !account.client_email || !account.private_key) throw new Error("fields");
    return account as ServiceAccount;
  } catch {
    throw new ApiError("FCM_NOT_CONFIGURED", 503);
  }
}

function jsonSegment(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function getAccessToken(env: Env, fetcher: typeof fetch, now: number): Promise<string> {
  if (accessTokenCache?.projectId === env.FIREBASE_PROJECT_ID && accessTokenCache.expiresAt > now + 60_000) {
    return accessTokenCache.value;
  }
  if (accessTokenPromise) return (await accessTokenPromise).value;
  const account = parseServiceAccount(env.FCM_SERVICE_ACCOUNT_JSON, env.FIREBASE_PROJECT_ID);
  accessTokenPromise = (async () => {
    const nowSec = Math.floor(now / 1000);
    const unsigned = `${jsonSegment({ alg: "RS256", typ: "JWT" })}.${jsonSegment({
      iss: account.client_email,
      scope: FCM_SCOPE,
      aud: TOKEN_URL,
      iat: nowSec,
      exp: nowSec + 3600,
    })}`;
    const pkcs8 = account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      toBufferSource(decodeBase64(pkcs8)),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, new TextEncoder().encode(unsigned));
    const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
    let response: Response;
    try {
      response = await fetcher(TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
      });
    } catch {
      throw new ApiError("FCM_AUTH_UNAVAILABLE", 503);
    }
    if (!response.ok) throw new ApiError("FCM_AUTH_UNAVAILABLE", 503);
    const body = (await response.json()) as { access_token?: string; expires_in?: number };
    if (!body.access_token || !body.expires_in) throw new ApiError("FCM_AUTH_UNAVAILABLE", 503);
    const token = { projectId: env.FIREBASE_PROJECT_ID, value: body.access_token, expiresAt: now + body.expires_in * 1000 };
    accessTokenCache = token;
    return token;
  })();
  try { return (await accessTokenPromise).value; } finally { accessTokenPromise = null; }
}

function retryDelay(attempts: number, retryAfter: string | null, now: number): number {
  if (retryAfter) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds) && seconds > 0) return Math.min(6 * 60 * 60_000, seconds * 1000);
    const date = Date.parse(retryAfter);
    if (Number.isFinite(date) && date > now) return Math.min(6 * 60 * 60_000, date - now);
  }
  return Math.min(6 * 60 * 60_000, 60_000 * 2 ** Math.min(6, Math.max(0, attempts - 1)));
}

function isInvalidRegistration(body: unknown): boolean {
  return JSON.stringify(body).includes("UNREGISTERED");
}

async function sendOne(
  token: string,
  message: { title: string; body: string; notificationId: string; taskId: string | null; eventType: string },
  env: Env,
  fetcher: typeof fetch,
  now: number,
) {
  const bearer = await getAccessToken(env, fetcher, now);
  let response: Response;
  try {
    response = await fetcher(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: message.title, body: message.body },
          data: { notificationId: message.notificationId, taskId: message.taskId ?? "", eventType: message.eventType },
          android: { priority: "high", ttl: "86400s", notification: { channel_id: "taskaty_alerts", click_action: "FLUTTER_NOTIFICATION_CLICK" } },
        },
      }),
    });
  } catch {
    return { ok: false, retry: true, code: "FCM_NETWORK_ERROR", invalid: false, retryAfter: null };
  }
  if (response.ok) return { ok: true, retry: false, code: null, invalid: false, retryAfter: null };
  let body: unknown;
  try { body = await response.json(); } catch { body = {}; }
  const invalid = (response.status === 404 || response.status === 400) && isInvalidRegistration(body);
  const transient = response.status === 429 || response.status >= 500 || response.status === 401;
  return { ok: false, retry: transient, code: `FCM_HTTP_${response.status}`, invalid, retryAfter: response.headers.get("retry-after") };
}

export async function dispatchOutbox(db: D1Database, env: Env, fetcher: typeof fetch = fetch, now = Date.now()) {
  if (!env.FCM_TOKEN_ENCRYPTION_KEY || !env.FCM_SERVICE_ACCOUNT_JSON) return 0;
  const timestamp = nowIso(now);
  const leaseUntil = nowIso(now + 2 * 60_000);
  const claimed = await db.prepare(
    `UPDATE notification_outbox SET status = 'sending', attempts = attempts + 1, lease_until = ?
     WHERE id IN (
       SELECT id FROM notification_outbox
       WHERE (status = 'pending' AND available_at <= ?) OR (status = 'sending' AND lease_until <= ?)
       ORDER BY available_at, created_at LIMIT ${MAX_DELIVERY_RECIPIENTS}
     ) RETURNING id, notification_id, recipient_user_id, task_id, attempts`,
  ).bind(leaseUntil, timestamp, timestamp).all<OutboxRow>();
  const rows = claimed.results ?? [];
  if (!rows.length) return 0;

  const ids = rows.map((row) => row.id);
  const placeholders = ids.map(() => "?").join(", ");
  const deliveries = await db.prepare(
    `WITH ranked_devices AS (
       SELECT token_hash, user_id, token_ciphertext, token_iv,
         ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY last_seen_at DESC, token_hash) AS device_rank
       FROM device_tokens WHERE invalidated_at IS NULL AND user_id IN (
         SELECT recipient_user_id FROM notification_outbox WHERE id IN (${placeholders})
       )
     )
     SELECT o.id, o.notification_id, o.recipient_user_id, o.task_id, o.attempts,
       n.title, n.body, n.type, d.token_hash, d.token_ciphertext, d.token_iv
     FROM notification_outbox o
     LEFT JOIN notifications n ON n.id = o.notification_id AND n.user_id = o.recipient_user_id
     LEFT JOIN ranked_devices d ON d.user_id = o.recipient_user_id AND d.device_rank <= ${MAX_DEVICES_PER_RECIPIENT}
     WHERE o.id IN (${placeholders})
     ORDER BY o.available_at, o.created_at, o.id, d.device_rank`,
  ).bind(...ids, ...ids).all<DeliveryQueryRow>();

  const grouped = new Map<string, Delivery>();
  for (const item of deliveries.results ?? []) {
    let delivery = grouped.get(item.id);
    if (!delivery) {
      const { title, body, type, token_hash: _tokenHash, token_ciphertext: _tokenCiphertext, token_iv: _tokenIv, ...outbox } = item;
      delivery = { outbox, title, body, type, devices: [] };
      grouped.set(item.id, delivery);
    }
    if (item.token_hash && item.token_ciphertext && item.token_iv) {
      delivery.devices.push({ token_hash: item.token_hash, token_ciphertext: item.token_ciphertext, token_iv: item.token_iv });
    }
  }

  const deletes: D1PreparedStatement[] = [];
  const updates: D1PreparedStatement[] = [];
  for (const row of rows) {
    const delivery = grouped.get(row.id);
    if (!delivery?.title || delivery.body === null || delivery.type === null) {
      updates.push(db.prepare("UPDATE notification_outbox SET status = 'dead', lease_until = NULL, last_error_code = 'NOTIFICATION_MISSING' WHERE id = ? AND status = 'sending'").bind(row.id));
      continue;
    }
    if (!delivery.devices.length) {
      updates.push(db.prepare("UPDATE notification_outbox SET status = 'no_device', lease_until = NULL WHERE id = ? AND status = 'sending'").bind(row.id));
      continue;
    }

    const deviceResults = await Promise.all(delivery.devices.map(async (device) => {
      try {
        const token = await decryptDeviceToken(device.token_ciphertext, device.token_iv, env.FCM_TOKEN_ENCRYPTION_KEY);
        const result = await sendOne(token, {
          title: delivery.title!,
          body: delivery.body!,
          notificationId: row.notification_id,
          taskId: row.task_id,
          eventType: delivery.type!,
        }, env, fetcher, now);
        return { device, result };
      } catch (error) {
        return { device, result: { ok: false, retry: true, code: error instanceof ApiError ? error.code : "FCM_SEND_FAILED", invalid: false, retryAfter: null } };
      }
    }));

    for (const { device, result } of deviceResults) if (result.invalid) deletes.push(db.prepare("DELETE FROM device_tokens WHERE token_hash = ?").bind(device.token_hash));
    const failures = deviceResults.map(({ result }) => result).filter((result) => !result.ok && !result.invalid);
    const failure = failures.find((result) => result.retry) ?? failures[0] ?? null;
    if (!failure) {
      updates.push(db.prepare("UPDATE notification_outbox SET status = 'sent', lease_until = NULL, delivered_at = ?, last_error_code = NULL WHERE id = ? AND status = 'sending'")
        .bind(timestamp, row.id));
    } else if (!failure.retry || row.attempts >= MAX_ATTEMPTS) {
      updates.push(db.prepare("UPDATE notification_outbox SET status = 'dead', lease_until = NULL, last_error_code = ? WHERE id = ? AND status = 'sending'")
        .bind(failure.code, row.id));
    } else {
      updates.push(db.prepare("UPDATE notification_outbox SET status = 'pending', available_at = ?, lease_until = NULL, last_error_code = ? WHERE id = ? AND status = 'sending'")
        .bind(nowIso(now + retryDelay(row.attempts, failure.retryAfter, now)), failure.code, row.id));
    }
  }
  const statements = [...deletes, ...updates];
  if (statements.length) await db.batch(statements);
  return rows.length;
}

export function resetFcmTokenCacheForTests(): void {
  accessTokenCache = null;
  accessTokenPromise = null;
}

export { MAX_DELIVERY_RECIPIENTS, MAX_DEVICES_PER_RECIPIENT };
