import { ApiError, requireInteger, requireString } from "./http.ts";
import { getMembership, requireRole } from "./data.ts";
import { base64Url, nowIso, randomId, sha256Hex } from "./http.ts";
import type { AuthUser, D1Database } from "./types.ts";

export async function listTeams(db: D1Database, userId: string) {
  const result = await db
    .prepare(
      `SELECT t.id, t.name, t.owner_id AS ownerId, t.created_at AS createdAt,
              tm.role, tm.joined_at AS joinedAt
       FROM team_members tm JOIN teams t ON t.id = tm.team_id
       WHERE tm.user_id = ? AND tm.left_at IS NULL ORDER BY tm.joined_at DESC LIMIT 100`,
    )
    .bind(userId)
    .all();
  return result.results ?? [];
}

export async function createTeam(db: D1Database, user: AuthUser, rawName: unknown, now = Date.now()) {
  const name = requireString(rawName, "name", 1, 80);
  const createdAt = nowIso(now);
  const id = randomId();
  await db.batch([
    db.prepare("INSERT INTO teams (id, name, owner_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)").bind(id, name, user.uid, createdAt, createdAt),
    db.prepare("INSERT INTO team_members (team_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)").bind(id, user.uid, createdAt),
    db.prepare("INSERT INTO team_metrics (team_id, updated_at) VALUES (?, ?)").bind(id, createdAt),
    db.prepare("INSERT INTO member_metrics (team_id, user_id, updated_at) VALUES (?, ?, ?)").bind(id, user.uid, createdAt),
    db.prepare(
      `INSERT INTO notifications (id, user_id, team_id, type, event_key, title, body, created_at)
       VALUES (?, ?, ?, 'team', ?, 'Taskaty', 'تم إنشاء الفريق بنجاح.', ?)`
    ).bind(randomId(), user.uid, id, `team-created:${id}`, createdAt),
  ]);
  return { id, name, ownerId: user.uid, role: "owner", createdAt };
}

export async function listMembers(db: D1Database, teamId: string, userId: string) {
  await getMembership(db, teamId, userId);
  const result = await db
    .prepare(
      `SELECT u.uid AS id, u.display_name AS displayName, u.email, u.photo_url AS photoUrl,
              tm.role, tm.joined_at AS joinedAt
       FROM team_members tm JOIN users u ON u.uid = tm.user_id
       WHERE tm.team_id = ? AND tm.left_at IS NULL ORDER BY CASE tm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
         u.display_name COLLATE NOCASE LIMIT 200`,
    )
    .bind(teamId)
    .all();
  return result.results ?? [];
}

export async function createInvitation(
  db: D1Database,
  teamId: string,
  userId: string,
  raw: { maxUses?: unknown; expiresInDays?: unknown; role?: unknown },
  now = Date.now(),
) {
  await requireRole(db, teamId, userId, ["owner", "admin"]);
  const maxUses = raw.maxUses === undefined ? 1 : requireInteger(raw.maxUses, "maxUses", 1, 50);
  const expiresInDays = raw.expiresInDays === undefined ? 7 : requireInteger(raw.expiresInDays, "expiresInDays", 1, 30);
  const role = raw.role === "admin" ? "admin" : raw.role === undefined || raw.role === "member" ? "member" : null;
  if (!role) throw new ApiError("INVALID_INPUT", 400, "role must be admin or member.");
  const random = crypto.getRandomValues(new Uint8Array(18));
  const code = base64Url(random);
  const createdAt = nowIso(now);
  const expiresAt = nowIso(now + expiresInDays * 86_400_000);
  await db
    .prepare(
      `INSERT INTO team_invitations (id, team_id, code_hash, role, created_by, created_at, expires_at, max_uses)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(randomId(), teamId, await sha256Hex(code), role, userId, createdAt, expiresAt, maxUses)
    .run();
  return { code, role, maxUses, expiresAt };
}

export async function joinTeam(db: D1Database, user: AuthUser, rawCode: unknown, now = Date.now()) {
  const code = requireString(rawCode, "code", 16, 64);
  const codeHash = await sha256Hex(code);
  const currentTime = nowIso(now);
  const invite = await db
    .prepare(
      `SELECT team_id, role FROM team_invitations
       WHERE code_hash = ? AND revoked_at IS NULL AND expires_at > ? AND used_count < max_uses`,
    )
    .bind(codeHash, currentTime)
    .first<{ team_id: string; role: "admin" | "member" }>();
  if (!invite) throw new ApiError("INVITATION_INVALID", 404, "This invitation is expired, revoked, or already used.");
  const existing = await db
    .prepare("SELECT 1 AS present FROM team_members WHERE team_id = ? AND user_id = ? AND left_at IS NULL")
    .bind(invite.team_id, user.uid)
    .first();
  if (existing) throw new ApiError("ALREADY_MEMBER", 409, "You already belong to this team.");
  const memberCount = await db.prepare("SELECT COUNT(*) AS count FROM team_members WHERE team_id = ? AND left_at IS NULL")
    .bind(invite.team_id).first<{ count: number }>();
  if ((memberCount?.count ?? 0) >= 200) throw new ApiError("TEAM_MEMBER_LIMIT", 409, "This team has reached its 200 active-member limit.");
  const historyCount = await db.prepare("SELECT COUNT(*) AS count FROM team_members WHERE team_id = ?")
    .bind(invite.team_id).first<{ count: number }>();
  if ((historyCount?.count ?? 0) >= 500) throw new ApiError("TEAM_LIFETIME_MEMBER_LIMIT", 409, "This team has reached its 500-member lifetime limit.");

  const results = await db.batch([
    db.prepare(
      `UPDATE team_invitations SET used_count = used_count + 1
       WHERE code_hash = ? AND revoked_at IS NULL AND expires_at > ? AND used_count < max_uses
         AND NOT EXISTS (SELECT 1 FROM team_members m WHERE m.team_id = team_invitations.team_id AND m.user_id = ? AND m.left_at IS NULL)
         AND (SELECT COUNT(*) FROM team_members m WHERE m.team_id = team_invitations.team_id AND m.left_at IS NULL) < 200
         AND (SELECT COUNT(*) FROM team_members m WHERE m.team_id = team_invitations.team_id) < 500
       RETURNING team_id, role`,
    ).bind(codeHash, currentTime, user.uid),
    db.prepare(
      `INSERT INTO team_members (team_id, user_id, role, joined_at)
       SELECT team_id, ?, role, ? FROM team_invitations
       WHERE code_hash = ? AND revoked_at IS NULL AND expires_at > ? AND used_count <= max_uses
       AND changes() > 0
       ON CONFLICT(team_id, user_id) DO UPDATE SET role = excluded.role, joined_at = excluded.joined_at, left_at = NULL
       WHERE team_members.left_at IS NOT NULL RETURNING team_id`,
    ).bind(user.uid, currentTime, codeHash, currentTime),
    db.prepare(
      `INSERT INTO member_metrics (team_id, user_id, updated_at)
       SELECT team_id, ?, ? FROM team_invitations WHERE code_hash = ? AND changes() > 0
       ON CONFLICT(team_id, user_id) DO NOTHING`,
    ).bind(user.uid, currentTime, codeHash),
    db.prepare(`UPDATE team_metrics SET revision = revision + 1, updated_at = ? WHERE team_id = ? AND EXISTS (
        SELECT 1 FROM team_members WHERE team_id = ? AND user_id = ? AND joined_at = ? AND left_at IS NULL
      )`).bind(currentTime, invite.team_id, invite.team_id, user.uid, currentTime),
    db.prepare(
      `INSERT INTO notifications (id, user_id, team_id, type, event_key, title, body, created_at)
       SELECT ?, user_id, team_id, 'team', ?, 'Taskaty', 'تم الانضمام إلى الفريق.', ? FROM team_members
       WHERE team_id = ? AND user_id = ? AND left_at IS NULL
       ON CONFLICT(user_id, event_key) DO NOTHING`,
    ).bind(randomId(), `team-joined:${invite.team_id}`, currentTime, invite.team_id, user.uid),
  ]);
  if (!(results[0]?.results?.length && results[1]?.results?.length)) {
    throw new ApiError("INVITATION_INVALID", 409, "This invitation has already reached its usage limit.");
  }
  return { teamId: invite.team_id, role: invite.role };
}

export async function leaveTeam(db: D1Database, teamId: string, userId: string, now = Date.now()) {
  const member = await getMembership(db, teamId, userId);
  if (member.role === "owner") throw new ApiError("OWNER_CANNOT_LEAVE", 409, "Transfer ownership before leaving this team.");
  const active = await db
    .prepare(
      `SELECT id FROM tasks WHERE team_id = ? AND assigned_to = ?
       AND status IN ('pending', 'in_progress') ORDER BY due_at LIMIT 1`,
    )
    .bind(teamId, userId)
    .first<{ id: string }>();
  if (active) throw new ApiError("ACTIVE_TASKS_REMAIN", 409, "Reassign or finish your active tasks before leaving.");
  const leftAt = nowIso(now);
  await db.batch([
      db.prepare("UPDATE team_members SET left_at = ? WHERE team_id = ? AND user_id = ? AND role <> 'owner' AND left_at IS NULL").bind(leftAt, teamId, userId),
    db.prepare("DELETE FROM member_metrics WHERE team_id = ? AND user_id = ?").bind(teamId, userId),
      db.prepare("UPDATE team_metrics SET revision = revision + 1, updated_at = ? WHERE team_id = ? AND EXISTS (SELECT 1 FROM team_members WHERE team_id = ? AND user_id = ? AND left_at = ?)")
        .bind(leftAt, teamId, teamId, userId, leftAt),
  ]);
  return { teamId, leftAt };
}
