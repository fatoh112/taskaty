import type { AuthUser, Env, FirebaseClaims } from "./types.ts";

const FIREBASE_KEYS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
const MAX_TOKEN_LENGTH = 8192;

interface FirebaseJwk extends JsonWebKey { kid?: string; kty?: string; alg?: string; use?: string }

interface KeyCache {
  keys: FirebaseJwk[];
  expiresAt: number;
}

let keyCache: KeyCache | null = null;
let keyFetchInFlight: Promise<KeyCache> | null = null;

export class AuthError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message = code,
  ) {
    super(message);
  }
}

function decodeBase64Url(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new AuthError("INVALID_TOKEN", 401);
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  try {
    const binary = atob(padded);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    throw new AuthError("INVALID_TOKEN", 401);
  }
}

function decodeJsonSegment<T>(segment: string): T {
  try {
    return JSON.parse(new TextDecoder().decode(decodeBase64Url(segment))) as T;
  } catch (error) {
    if (error instanceof AuthError) throw error;
    throw new AuthError("INVALID_TOKEN", 401);
  }
}

async function loadKeys(fetcher: typeof fetch, force = false): Promise<KeyCache> {
  const now = Date.now();
  if (!force && keyCache && keyCache.expiresAt > now) return keyCache;
  if (!force && keyFetchInFlight) return keyFetchInFlight;

  keyFetchInFlight = (async () => {
    let response: Response;
    try {
      response = await fetcher(FIREBASE_KEYS_URL, { headers: { Accept: "application/json" } });
    } catch {
      throw new AuthError("AUTH_VERIFICATION_UNAVAILABLE", 503);
    }
    if (!response.ok) throw new AuthError("AUTH_VERIFICATION_UNAVAILABLE", 503);
    let body: { keys?: FirebaseJwk[] };
    try {
      body = (await response.json()) as { keys?: JsonWebKey[] };
    } catch {
      throw new AuthError("AUTH_VERIFICATION_UNAVAILABLE", 503);
    }
    if (!Array.isArray(body.keys) || body.keys.length === 0) {
      throw new AuthError("AUTH_VERIFICATION_UNAVAILABLE", 503);
    }
    const cacheControl = response.headers.get("cache-control") ?? "";
    const maxAge = Number(cacheControl.match(/max-age=(\d+)/i)?.[1] ?? 3600);
    const freshForMs = Math.max(60, Math.min(21600, maxAge)) * 1000;
    const next = { keys: body.keys, expiresAt: now + freshForMs };
    keyCache = next;
    return next;
  })();

  try {
    return await keyFetchInFlight;
  } finally {
    keyFetchInFlight = null;
  }
}

function hasAudience(aud: string | string[], projectId: string): boolean {
  return typeof aud === "string" ? aud === projectId : aud.length === 1 && aud[0] === projectId;
}

export async function verifyFirebaseIdToken(
  token: string,
  projectId: string,
  fetcher: typeof fetch = fetch,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<FirebaseClaims> {
  if (!projectId || token.length > MAX_TOKEN_LENGTH) throw new AuthError("INVALID_TOKEN", 401);
  const parts = token.split(".");
  if (parts.length !== 3) throw new AuthError("INVALID_TOKEN", 401);
  const [encodedHeader, encodedClaims, encodedSignature] = parts;
  const header = decodeJsonSegment<{ alg?: string; kid?: string; typ?: string }>(encodedHeader);
  const claims = decodeJsonSegment<FirebaseClaims>(encodedClaims);
  if (header.alg !== "RS256" || typeof header.kid !== "string" || header.kid.length > 256) {
    throw new AuthError("INVALID_TOKEN", 401);
  }
  if (
    claims.iss !== `https://securetoken.google.com/${projectId}` ||
    !hasAudience(claims.aud, projectId) ||
    typeof claims.sub !== "string" ||
    claims.sub.length === 0 ||
    claims.sub.length > 128 ||
    (claims.user_id !== undefined && claims.user_id !== claims.sub) ||
    !Number.isInteger(claims.exp) ||
    !Number.isInteger(claims.iat) ||
    !Number.isInteger(claims.auth_time) ||
    claims.exp <= nowSeconds ||
    claims.iat > nowSeconds + 60 ||
    claims.auth_time > nowSeconds + 60
  ) {
    throw new AuthError(claims.exp <= nowSeconds ? "TOKEN_EXPIRED" : "INVALID_TOKEN", 401);
  }

  let keys = await loadKeys(fetcher);
  let jwk = keys.keys.find((candidate) => candidate.kid === header.kid && candidate.kty === "RSA");
  if (!jwk) {
    keys = await loadKeys(fetcher, true);
    jwk = keys.keys.find((candidate) => candidate.kid === header.kid && candidate.kty === "RSA");
  }
  if (!jwk) throw new AuthError("INVALID_TOKEN", 401);

  try {
    const publicKey = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const signingInput = new TextEncoder().encode(`${encodedHeader}.${encodedClaims}`);
    const valid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      publicKey,
      toBufferSource(decodeBase64Url(encodedSignature)),
      toBufferSource(signingInput),
    );
    if (!valid) throw new AuthError("INVALID_TOKEN", 401);
  } catch (error) {
    if (error instanceof AuthError) throw error;
    throw new AuthError("INVALID_TOKEN", 401);
  }
  return claims;
}

function toBufferSource(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

export async function authenticateRequest(request: Request, env: Env): Promise<AuthUser> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer ([^\s]+)$/i.exec(header);
  if (!match) throw new AuthError("AUTH_REQUIRED", 401);
  const claims = await verifyFirebaseIdToken(match[1], env.FIREBASE_PROJECT_ID);
  if (claims.email_verified !== true) throw new AuthError("EMAIL_NOT_VERIFIED", 403);
  return {
    uid: claims.sub,
    email: typeof claims.email === "string" ? claims.email.slice(0, 254) : "",
    displayName: typeof claims.name === "string" ? claims.name.slice(0, 120) : "",
    photoUrl: typeof claims.picture === "string" ? claims.picture.slice(0, 2048) : null,
    emailVerified: true,
  };
}

export function resetFirebaseKeyCacheForTests(): void {
  keyCache = null;
  keyFetchInFlight = null;
}
