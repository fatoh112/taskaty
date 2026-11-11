import { authenticateRequest } from "./auth.ts";
import { createInvitation, createTeam, joinTeam, leaveTeam, listMembers, listTeams } from "./teams.ts";
import { createTask, getDashboard, getTask, getTaskActivity, listTasks, updateTask } from "./tasks.ts";
import { listNotifications, markNotificationRead, registerDevice, unregisterDevice } from "./notifications.ts";
import { ApiError, errorResponse, jsonResponse, readJson, nowIso, sha256Hex } from "./http.ts";
import { rateLimit, syncUser } from "./data.ts";
import { runScheduledWork } from "./scheduler.ts";
import type { Env, ExecutionContext, ScheduledController } from "./types.ts";

function notModified(request: Request, env: Env, etag: string): Response {
  const headers = new Headers({
    "Access-Control-Allow-Origin": env.APP_ORIGIN && request.headers.get("origin") === env.APP_ORIGIN ? env.APP_ORIGIN : env.APP_ORIGIN ? "null" : "*",
    "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization,Content-Type,Idempotency-Key,If-None-Match",
    "Access-Control-Max-Age": "600",
    "Cache-Control": "no-store",
    ETag: etag,
    Vary: "Origin",
  });
  return new Response(null, { status: 304, headers });
}

async function health(request: Request, env: Env): Promise<Response> {
  const heartbeat = await env.DB.prepare(
    "SELECT last_started_at AS lastStartedAt, last_finished_at AS lastFinishedAt, last_error_code AS lastErrorCode FROM worker_heartbeats WHERE name = 'taskpulse'",
  ).first<{ lastStartedAt: string | null; lastFinishedAt: string | null; lastErrorCode: string | null }>();
  const now = Date.now();
  const last = heartbeat?.lastFinishedAt ? Date.parse(heartbeat.lastFinishedAt) : null;
  return jsonResponse(request, env, {
    status: heartbeat?.lastErrorCode ? "degraded" : "ok",
    serverTime: nowIso(now),
    scheduler: {
      lastStartedAt: heartbeat?.lastStartedAt ?? null,
      lastFinishedAt: heartbeat?.lastFinishedAt ?? null,
      lastErrorCode: heartbeat?.lastErrorCode ?? null,
      delaySeconds: last === null ? null : Math.max(0, Math.floor((now - last) / 1000)),
    },
  }, heartbeat?.lastErrorCode ? 503 : 200);
}

async function authenticatedFetch(request: Request, env: Env): Promise<Response> {
  const user = await authenticateRequest(request, env);
  const now = Date.now();
  await rateLimit(env.DB, user.uid, "api", now);
  await syncUser(env.DB, user, nowIso(now));
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = request.method.toUpperCase();

  if (path === "/v1/me" && method === "GET") {
    const stored = await env.DB.prepare(
      "SELECT uid AS id, email, display_name AS displayName, photo_url AS photoUrl, created_at AS createdAt, updated_at AS updatedAt FROM users WHERE uid = ?",
    ).bind(user.uid).first();
    return jsonResponse(request, env, stored);
  }
  if (path === "/v1/teams" && method === "GET") return jsonResponse(request, env, { items: await listTeams(env.DB, user.uid) });
  if (path === "/v1/teams" && method === "POST") {
    const body = await readJson(request);
    return jsonResponse(request, env, { team: await createTeam(env.DB, user, body.name, now) }, 201);
  }
  if (path === "/v1/teams/join" && method === "POST") {
    const body = await readJson(request);
    return jsonResponse(request, env, await joinTeam(env.DB, user, body.code, now), 201);
  }
  if (path === "/v1/notifications" && method === "GET") {
    return jsonResponse(request, env, await listNotifications(env.DB, user.uid, url.searchParams));
  }
  if (path === "/v1/devices/register" && method === "POST") {
    return jsonResponse(request, env, await registerDevice(env.DB, user.uid, await readJson(request), env.FCM_TOKEN_ENCRYPTION_KEY, now), 201);
  }
  if (path === "/v1/devices/unregister" && method === "POST") {
    const body = await readJson(request);
    return jsonResponse(request, env, await unregisterDevice(env.DB, user.uid, body.token));
  }

  const teamMatch = /^\/v1\/teams\/([^/]+)(?:\/(members|invitations|join|leave|tasks|dashboard))?$/.exec(path);
  if (teamMatch) {
    const teamId = decodeURIComponent(teamMatch[1]);
    const route = teamMatch[2];
    if ((!route || route === "dashboard") && method === "GET") {
      const role = await env.DB.prepare("SELECT role FROM team_members WHERE team_id = ? AND user_id = ? AND left_at IS NULL")
        .bind(teamId, user.uid).first<{ role: string }>();
      if (!role) throw new ApiError("TEAM_NOT_FOUND", 404);
      const revision = await env.DB.prepare("SELECT revision FROM team_metrics WHERE team_id = ?").bind(teamId).first<{ revision: number }>();
      const etag = `"${teamId}:${revision?.revision ?? 0}"`;
      if (request.headers.get("if-none-match") === etag) return notModified(request, env, etag);
      return jsonResponse(request, env, await getDashboard(env.DB, teamId, user.uid, now), 200, { ETag: etag });
    }
    if (route === "members" && method === "GET") return jsonResponse(request, env, { items: await listMembers(env.DB, teamId, user.uid) });
    if (route === "invitations" && method === "POST") {
      const body = await readJson(request);
      return jsonResponse(request, env, await createInvitation(env.DB, teamId, user.uid, body, now), 201);
    }
    if (route === "leave" && method === "POST") return jsonResponse(request, env, await leaveTeam(env.DB, teamId, user.uid, now));
    if (route === "tasks" && method === "GET") {
      const member = await env.DB.prepare("SELECT 1 AS present FROM team_members WHERE team_id = ? AND user_id = ? AND left_at IS NULL")
        .bind(teamId, user.uid).first();
      if (!member) throw new ApiError("TEAM_NOT_FOUND", 404);
      const revision = await env.DB.prepare("SELECT revision FROM team_metrics WHERE team_id = ?").bind(teamId).first<{ revision: number }>();
      const queryHash = await sha256Hex(url.searchParams.toString());
      const etag = `"${teamId}:tasks:${revision?.revision ?? 0}:${queryHash}"`;
      if (request.headers.get("if-none-match") === etag) return notModified(request, env, etag);
      return jsonResponse(request, env, await listTasks(env.DB, teamId, user.uid, url.searchParams, now), 200, { ETag: etag });
    }
    if (route === "tasks" && method === "POST") {
      const body = await readJson(request);
      const key = request.headers.get("idempotency-key");
      return jsonResponse(request, env, { task: await createTask(env.DB, user, teamId, body, key, now) }, 201);
    }
    if (route === "dashboard" && method === "GET") return jsonResponse(request, env, await getDashboard(env.DB, teamId, user.uid, now));
  }

  const notificationMatch = /^\/v1\/notifications\/([^/]+)\/read$/.exec(path);
  if (notificationMatch && method === "POST") {
    return jsonResponse(request, env, await markNotificationRead(env.DB, decodeURIComponent(notificationMatch[1]), user.uid, now));
  }

  const taskMatch = /^\/v1\/tasks\/([^/]+)(?:\/(activity|start|complete|cancel))?$/.exec(path);
  if (taskMatch) {
    const taskId = decodeURIComponent(taskMatch[1]);
    const action = taskMatch[2];
    if (!action && method === "GET") return jsonResponse(request, env, { task: await getTask(env.DB, taskId, user.uid) });
    if (action === "activity" && method === "GET") return jsonResponse(request, env, { items: await getTaskActivity(env.DB, taskId, user.uid) });
    if ((method === "PATCH" || (method === "POST" && !!action)) && (!action || ["start", "complete", "cancel"].includes(action))) {
      const body = await readJson(request);
      const status = action === "start" ? "in_progress" : action === "complete" ? "completed" : action === "cancel" ? "cancelled" : body.status;
      return jsonResponse(request, env, { task: await updateTask(env.DB, taskId, user.uid, { ...body, ...(status ? { status } : {}) }, now) });
    }
  }
  throw new ApiError("NOT_FOUND", 404, "API endpoint was not found.");
}

const worker = {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: {
        "Access-Control-Allow-Origin": env.APP_ORIGIN && request.headers.get("origin") === env.APP_ORIGIN ? env.APP_ORIGIN : env.APP_ORIGIN ? "null" : "*",
        "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
        "Access-Control-Allow-Headers": "Authorization,Content-Type,Idempotency-Key,If-None-Match",
        "Access-Control-Max-Age": "600",
        Vary: "Origin",
      } });
    }
    try {
      if (url.pathname === "/health" && request.method === "GET") return await health(request, env);
      if (!url.pathname.startsWith("/v1/")) throw new ApiError("NOT_FOUND", 404, "API endpoint was not found.");
      return await authenticatedFetch(request, env);
    } catch (error) {
      return errorResponse(request, env, error);
    }
  },
  async scheduled(controller: ScheduledController, env: Env, _ctx: ExecutionContext): Promise<void> {
    await runScheduledWork(env.DB, env, controller);
  },
};

export default worker;
