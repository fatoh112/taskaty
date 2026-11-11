import { ApiError, decodeBase64, encodeBase64, nowIso, requireString, sha256Hex } from "./http.ts";
import { decodeCursor, encodeCursor } from "./data.ts";
import type { D1Database } from "./types.ts";

function toBufferSource(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function encryptionKey(secret?: string): Promise<CryptoKey> {
  if (!secret) throw new ApiError("PUSH_NOT_CONFIGURED", 503, "Push notification setup is incomplete.");
  let raw: Uint8Array;
  try { raw = decodeBase64(secret); } catch { throw new ApiError("PUSH_NOT_CONFIGURED", 503, "Push notification setup is incomplete."); }
  if (raw.byteLength !== 32) throw new ApiError("PUSH_NOT_CONFIGURED", 503, "Push notification key must be 32 bytes.");
  return crypto.subtle.importKey("raw", toBufferSource(raw), { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

export async function encryptDeviceToken(token: string, secret?: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await encryptionKey(secret);
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv: toBufferSource(iv) }, key, new TextEncoder().encode(token));
  return { tokenIv: encodeBase64(iv), tokenCiphertext: encodeBase64(new Uint8Array(ciphertext)) };
}

export async function decryptDeviceToken(ciphertext: string, iv: string, secret?: string): Promise<string> {
  const key = await encryptionKey(secret);
  const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv: toBufferSource(decodeBase64(iv)) }, key, toBufferSource(decodeBase64(ciphertext)));
  return new TextDecoder().decode(plaintext);
}

export async function registerDevice(db: D1Database, userId: string, raw: Record<string, unknown>, encryptionSecret?: string, now = Date.now()) {
  const token = requireString(raw.token, "token", 32, 8192);
  const platform = raw.platform;
  if (!(["android", "ios", "web"] as unknown[]).includes(platform)) throw new ApiError("INVALID_INPUT", 400, "platform is invalid.");
  const tokenHash = await sha256Hex(token);
  const encrypted = await encryptDeviceToken(token, encryptionSecret);
  const timestamp = nowIso(now);
  const result = await db.prepare(
    `INSERT INTO device_tokens (token_hash, user_id, token_ciphertext, token_iv, platform, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(token_hash) DO UPDATE SET token_ciphertext = excluded.token_ciphertext,
       token_iv = excluded.token_iv, platform = excluded.platform, last_seen_at = excluded.last_seen_at,
       invalidated_at = NULL WHERE device_tokens.user_id = excluded.user_id RETURNING token_hash`,
  ).bind(tokenHash, userId, encrypted.tokenCiphertext, encrypted.tokenIv, platform, timestamp, timestamp).first<{ token_hash: string }>();
  if (!result) throw new ApiError("DEVICE_TOKEN_OWNED", 409, "This device registration belongs to another account.");
  return { registered: true };
}

export async function unregisterDevice(db: D1Database, userId: string, rawToken: unknown) {
  const token = requireString(rawToken, "token", 32, 8192);
  await db.prepare("DELETE FROM device_tokens WHERE token_hash = ? AND user_id = ?").bind(await sha256Hex(token), userId).run();
  return { unregistered: true };
}

export async function listNotifications(db: D1Database, userId: string, query: URLSearchParams) {
  const limit = Math.max(1, Math.min(100, Number.parseInt(query.get("limit") ?? "30", 10) || 30));
  const cursor = decodeCursor(query.get("cursor"));
  const filters = ["user_id = ?"];
  const params: unknown[] = [userId];
  if (query.get("unread") === "true") filters.push("read_at IS NULL");
  if (cursor) {
    filters.push("(created_at < ? OR (created_at = ? AND id < ?))");
    params.push(cursor[0], cursor[0], cursor[1]);
  }
  params.push(limit + 1);
  const result = await db.prepare(
    `SELECT id, team_id AS teamId, task_id AS taskId, type, title, body, created_at AS createdAt, read_at AS readAt
     FROM notifications WHERE ${filters.join(" AND ")} ORDER BY created_at DESC, id DESC LIMIT ?`,
  ).bind(...params).all<Record<string, unknown>>();
  const items = result.results ?? [];
  const page = items.slice(0, limit);
  const tail = page[page.length - 1];
  const unread = await db.prepare("SELECT COUNT(*) AS count FROM notifications WHERE user_id = ? AND read_at IS NULL")
    .bind(userId).first<{ count: number }>();
  return {
    items: page,
    nextCursor: items.length > limit && tail ? encodeCursor([tail.createdAt as string, tail.id as string]) : null,
    unreadCount: unread?.count ?? 0,
  };
}

export async function markNotificationRead(db: D1Database, notificationId: string, userId: string, now = Date.now()) {
  const result = await db.prepare(
    "UPDATE notifications SET read_at = COALESCE(read_at, ?) WHERE id = ? AND user_id = ? RETURNING id, read_at",
  ).bind(nowIso(now), notificationId, userId).first<{ id: string; read_at: string }>();
  if (!result) throw new ApiError("NOTIFICATION_NOT_FOUND", 404);
  return { id: result.id, readAt: result.read_at };
}
