import { beforeEach, describe, expect, it } from "vitest";
import { base64Url } from "../worker/src/http.ts";
import { resetFirebaseKeyCacheForTests, verifyFirebaseIdToken } from "../worker/src/auth.ts";
import { makeFirebaseTestToken, projectId, setupTestKeys, testKeyFetcher, currentTestPrivateKey } from "./support/firebase-token.ts";

beforeEach(async () => { resetFirebaseKeyCacheForTests(); await setupTestKeys(); });

describe("Firebase ID token validation", () => {
  it("accepts a correctly signed Firebase token with valid required claims", async () => {
    const claims = await verifyFirebaseIdToken(await makeFirebaseTestToken(), projectId, testKeyFetcher);
    expect(claims.sub).toBe("test-user");
    expect(claims.aud).toBe(projectId);
  });

  it("rejects expired, wrong-audience, wrong-issuer, and unsigned tokens", async () => {
    const now = Math.floor(Date.now() / 1000);
    await expect(verifyFirebaseIdToken(await makeFirebaseTestToken({ exp: now - 10 }), projectId, testKeyFetcher)).rejects.toMatchObject({ status: 401 });
    await expect(verifyFirebaseIdToken(await makeFirebaseTestToken({ aud: "other-project" }), projectId, testKeyFetcher)).rejects.toMatchObject({ status: 401 });
    await expect(verifyFirebaseIdToken(await makeFirebaseTestToken({ iss: "https://attacker.test" }), projectId, testKeyFetcher)).rejects.toMatchObject({ status: 401 });
    await expect(verifyFirebaseIdToken(await makeFirebaseTestToken({}, false), projectId, testKeyFetcher)).rejects.toMatchObject({ status: 401 });
  });

  it("rejects a bad signature even when the claims look valid", async () => {
    const signed = await makeFirebaseTestToken();
    const parts = signed.split(".");
    parts[2] = base64Url(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", currentTestPrivateKey()!, new TextEncoder().encode("different signing input"))));
    await expect(verifyFirebaseIdToken(parts.join("."), projectId, testKeyFetcher)).rejects.toMatchObject({ status: 401 });
  });

  it("fails closed when Google signing keys are unavailable", async () => {
    await expect(verifyFirebaseIdToken(await makeFirebaseTestToken(), projectId, async () => { throw new Error("offline"); }))
      .rejects.toMatchObject({ code: "AUTH_VERIFICATION_UNAVAILABLE", status: 503 });
  });
});
