import { AuthError } from "./auth.ts";
import type { Env } from "./types.ts";

export class ApiError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message = code,
  ) {
    super(message);
  }
}

export function corsHeaders(request: Request, env: Env): HeadersInit {
  const origin = request.headers.get("origin");
  const allowed = env.APP_ORIGIN;
  return {
    ...(allowed && origin === allowed ? { "Access-Control-Allow-Origin": allowed } : {}),
    "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization,Content-Type,Idempotency-Key,If-None-Match",
    "Access-Control-Max-Age": "600",
    Vary: "Origin",
  };
}

export function preflightResponse(request: Request, env: Env): Response {
  if (!env.APP_ORIGIN || request.headers.get("origin") !== env.APP_ORIGIN) {
    return new Response(null, { status: 403 });
  }
  return new Response(null, { status: 204, headers: corsHeaders(request, env) });
}

export function jsonResponse(request: Request, env: Env, body: unknown, status = 200, extra?: HeadersInit): Response {
  const headers = new Headers(corsHeaders(request, env));
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  if (extra) new Headers(extra).forEach((value, key) => headers.set(key, value));
  return new Response(JSON.stringify(body), { status, headers });
}

export function errorResponse(request: Request, env: Env, error: unknown): Response {
  if (error instanceof ApiError || error instanceof AuthError) {
    return jsonResponse(request, env, { error: { code: error.code, message: safeMessage(error.message) } }, error.status);
  }
  const message = error instanceof Error ? error.message : "Unexpected error";
  const code = /D1|SQLITE|database|quota/i.test(message) ? "STORAGE_TEMPORARILY_UNAVAILABLE" : "INTERNAL_ERROR";
  return jsonResponse(request, env, { error: { code, message: "The request could not be completed." } }, code === "INTERNAL_ERROR" ? 500 : 503);
}

function safeMessage(message: string): string {
  return message.length > 160 ? message.slice(0, 160) : message;
}

export async function readJson<T extends Record<string, unknown>>(request: Request, maxBytes = 20_000): Promise<T> {
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > maxBytes) throw new ApiError("REQUEST_TOO_LARGE", 413);
  let text: string;
  try {
    text = await request.text();
  } catch {
    throw new ApiError("INVALID_JSON", 400);
  }
  if (new TextEncoder().encode(text).length > maxBytes) throw new ApiError("REQUEST_TOO_LARGE", 413);
  try {
    const value: unknown = JSON.parse(text);
    if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error("object required");
    return value as T;
  } catch {
    throw new ApiError("INVALID_JSON", 400);
  }
}

export function requireString(value: unknown, field: string, min = 1, max = 240): string {
  if (typeof value !== "string") throw new ApiError("INVALID_INPUT", 400, `${field} must be text.`);
  const normalized = value.trim();
  if (normalized.length < min || normalized.length > max) {
    throw new ApiError("INVALID_INPUT", 400, `${field} length is invalid.`);
  }
  return normalized;
}

export function optionalString(value: unknown, field: string, max: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new ApiError("INVALID_INPUT", 400, `${field} must be text.`);
  const normalized = value.trim();
  if (normalized.length > max) throw new ApiError("INVALID_INPUT", 400, `${field} is too long.`);
  return normalized || null;
}

export function requireInteger(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    throw new ApiError("INVALID_INPUT", 400, `${field} must be an integer between ${min} and ${max}.`);
  }
  return value;
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function randomId(): string {
  return crypto.randomUUID();
}

export function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function decodeBase64(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

export function encodeBase64(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function nowIso(now = Date.now()): string {
  return new Date(now).toISOString();
}
