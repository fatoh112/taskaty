import { base64Url } from "../../worker/src/http.ts";

export const projectId = "taskpulse-test";
let keys: CryptoKeyPair | undefined;
let publicJwk: (JsonWebKey & { kid?: string; alg?: string; use?: string }) | undefined;

function segment(value: unknown) { return base64Url(new TextEncoder().encode(JSON.stringify(value))); }

export async function setupTestKeys() {
  if (keys && publicJwk) return;
  keys = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  publicJwk = { ...(await crypto.subtle.exportKey("jwk", keys.publicKey)), kid: "test-key", alg: "RS256", use: "sig" };
}

export async function makeFirebaseTestToken(overrides: Record<string, unknown> = {}, signed = true) {
  await setupTestKeys();
  const now = Math.floor(Date.now() / 1000);
  const header = segment({ alg: "RS256", kid: "test-key", typ: "JWT" });
  const claims = segment({
    iss: `https://securetoken.google.com/${projectId}`,
    aud: projectId,
    sub: "test-user",
    user_id: "test-user",
    exp: now + 3600,
    iat: now,
    auth_time: now,
    email_verified: true,
    email: "member@example.test",
    ...overrides,
  });
  if (!signed) return `${header}.${claims}.`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", keys!.privateKey, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
}

export const testKeyFetcher: typeof fetch = async () => {
  await setupTestKeys();
  return new Response(JSON.stringify({ keys: [publicJwk] }), {
    status: 200,
    headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" },
  });
};

export function currentTestPublicJwk() { return publicJwk; }
export function currentTestPrivateKey() { return keys?.privateKey; }
