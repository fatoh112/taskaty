import { ApiError } from "./http.ts";
import type { AuthUser, D1Database } from "./types.ts";

export interface Membership {
  team_id: string;
  user_id: string;
  role: "owner" | "admin" | "member";
  joined_at: string;
  left_at: string | null;
}

export async function syncUser(db: D1Database, user: AuthUser, now: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO users (uid, email, display_name, photo_url, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(uid) DO UPDATE SET email = excluded.email,
         display_name = excluded.display_name, photo_url = excluded.photo_url, updated_at = excluded.updated_at
       WHERE users.email IS NOT excluded.email OR users.display_name IS NOT excluded.display_name
         OR users.photo_url IS NOT excluded.photo_url`,
    )
    .bind(user.uid, user.email || `${user.uid}@firebase.invalid`, user.displayName || "Taskaty member", user.photoUrl, now, now)
    .run();
}

export async function getMembership(db: D1Database, teamId: string, userId: string): Promise<Membership> {
  const member = await db
    .prepare("SELECT team_id, user_id, role, joined_at, left_at FROM team_members WHERE team_id = ? AND user_id = ? AND left_at IS NULL")
    .bind(teamId, userId)
    .first<Membership>();
  if (!member) throw new ApiError("TEAM_NOT_FOUND", 404, "Team was not found.");
  return member;
}

export async function requireRole(
  db: D1Database,
  teamId: string,
  userId: string,
  allowed: readonly Membership["role"][],
): Promise<Membership> {
  const member = await getMembership(db, teamId, userId);
  if (!allowed.includes(member.role)) throw new ApiError("FORBIDDEN", 403, "This team action is not allowed for your role.");
  return member;
}

export async function rateLimit(
  db: D1Database,
  userId: string,
  scope: string,
  nowMs: number,
  limit = 180,
): Promise<void> {
  const windowStart = Math.floor(nowMs / 60_000) * 60;
  const result = await db
    .prepare(
      `INSERT INTO api_rate_limits (bucket_key, window_start, request_count)
       VALUES (?, ?, 1)
       ON CONFLICT(bucket_key, window_start) DO UPDATE SET request_count = request_count + 1
       RETURNING request_count`,
    )
    .bind(`${userId}:${scope}`, windowStart)
    .first<{ request_count: number }>();
  if ((result?.request_count ?? limit + 1) > limit) throw new ApiError("RATE_LIMITED", 429, "Slow down and try again shortly.");
  if (windowStart % 1800 === 0) {
    await db.prepare("DELETE FROM api_rate_limits WHERE window_start < ?").bind(windowStart - 3600).run();
  }
}

export function encodeCursor(values: unknown[]): string {
  const json = JSON.stringify(values);
  return btoa(json).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function decodeCursor(cursor: string | null): unknown[] | null {
  if (!cursor) return null;
  if (!/^[A-Za-z0-9_-]{1,512}$/.test(cursor)) throw new ApiError("INVALID_CURSOR", 400);
  try {
    const padded = cursor.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(cursor.length / 4) * 4, "=");
    const value: unknown = JSON.parse(atob(padded));
    if (!Array.isArray(value) || value.length !== 2 || !value.every((part) => typeof part === "string")) {
      throw new Error("bad cursor");
    }
    return value;
  } catch {
    throw new ApiError("INVALID_CURSOR", 400);
  }
}
