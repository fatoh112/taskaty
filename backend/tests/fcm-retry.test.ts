import { afterEach, describe, expect, it } from "vitest";
import { dispatchOutbox, resetFcmTokenCacheForTests } from "../worker/src/fcm.ts";
import { encryptDeviceToken } from "../worker/src/notifications.ts";
import { createMemoryD1 } from "./support/memory-d1.ts";
import { encodeBase64, nowIso } from "../worker/src/http.ts";
import type { Env } from "../worker/src/types.ts";

const key = crypto.getRandomValues(new Uint8Array(32));
const encryptionSecret = encodeBase64(key);
let db: Awaited<ReturnType<typeof createMemoryD1>> | undefined;
afterEach(() => { db?.close(); db = undefined; resetFcmTokenCacheForTests(); });

describe("FCM outbox retry policy", () => {
  it("retries a transient FCM failure with backoff and then marks delivery sent", async () => {
    db = await createMemoryD1();
    const now = Date.now();
    const createdAt = nowIso(now);
    const accountKeys = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
    const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", accountKeys.privateKey));
    const privateKey = encodeBase64(pkcs8).match(/.{1,64}/g)!.join("\n");
    const serviceAccount = JSON.stringify({
      type: "service_account",
      project_id: "taskpulse-test",
      client_email: "worker@taskpulse-test.iam.gserviceaccount.com",
      private_key: `-----BEGIN PRIVATE KEY-----\n${privateKey}\n-----END PRIVATE KEY-----\n`,
    });
    await db.exec(`
      INSERT INTO users (uid,email,display_name,created_at,updated_at) VALUES ('u','u@example.test','U','${createdAt}','${createdAt}');
      INSERT INTO teams (id,name,owner_id,created_at,updated_at) VALUES ('t','Team','u','${createdAt}','${createdAt}');
      INSERT INTO team_members (team_id,user_id,role,joined_at) VALUES ('t','u','owner','${createdAt}');
      INSERT INTO tasks (id,team_id,title,created_by,assigned_to,created_at,updated_at,duration_minutes,due_at)
        VALUES ('task','t','Task','u','u','${createdAt}','${createdAt}',60,'${nowIso(now+3600000)}');
      INSERT INTO notifications (id,user_id,team_id,task_id,type,event_key,title,body,created_at)
        VALUES ('n','u','t','task','overdue','event','Taskaty','An overdue task is in your team.','${createdAt}');
      INSERT INTO notification_outbox (id,notification_id,recipient_user_id,task_id,status,available_at,created_at)
        VALUES ('o','n','u','task','pending','${createdAt}','${createdAt}');
    `);
    const token = `fcm-registration-token-${"x".repeat(100)}`;
    const encrypted = await encryptDeviceToken(token, encryptionSecret);
    await db.prepare(`INSERT INTO device_tokens (token_hash,user_id,token_ciphertext,token_iv,platform,created_at,last_seen_at)
      VALUES ('hash','u',?,?, 'android',?,?)`).bind(encrypted.tokenCiphertext, encrypted.tokenIv, createdAt, createdAt).run();
    const env: Env = {
      DB: db,
      FIREBASE_PROJECT_ID: "taskpulse-test",
      FCM_SERVICE_ACCOUNT_JSON: serviceAccount,
      FCM_TOKEN_ENCRYPTION_KEY: encryptionSecret,
    };
    let sends = 0;
    const mockFetch: typeof fetch = async (input) => {
      const url = String(input);
      if (url === "https://oauth2.googleapis.com/token") {
        return new Response(JSON.stringify({ access_token: "test-access-token", expires_in: 3600 }), { status: 200 });
      }
      if (url.includes("fcm.googleapis.com")) {
        sends++;
        return sends === 1
          ? new Response(JSON.stringify({ error: { status: "UNAVAILABLE" } }), { status: 503 })
          : new Response(JSON.stringify({ name: "projects/taskpulse-test/messages/test" }), { status: 200 });
      }
      throw new Error(`Unexpected URL: ${url}`);
    };
    expect(await dispatchOutbox(db, env, mockFetch, now)).toBe(1);
    const pending = await db.prepare("SELECT status, attempts, available_at FROM notification_outbox WHERE id='o'").first<{ status: string; attempts: number; available_at: string }>();
    expect(pending?.status).toBe("pending");
    expect(pending?.attempts).toBe(1);
    expect(Date.parse(pending!.available_at)).toBe(now + 60_000);
    expect(await dispatchOutbox(db, env, mockFetch, now + 61_000)).toBe(1);
    const sent = await db.prepare("SELECT status, attempts, delivered_at FROM notification_outbox WHERE id='o'").first<{ status: string; attempts: number; delivered_at: string }>();
    expect(sent?.status).toBe("sent");
    expect(sent?.attempts).toBe(2);
    expect(sent?.delivered_at).toBe(nowIso(now + 61_000));
  });
});
