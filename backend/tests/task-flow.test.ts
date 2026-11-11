import { beforeAll, afterEach, describe, expect, it, vi } from "vitest";
import worker from "../worker/src/index.ts";
import { createMemoryD1 } from "./support/memory-d1.ts";
import { makeFirebaseTestToken, setupTestKeys, testKeyFetcher, projectId as testProjectId } from "./support/firebase-token.ts";
import type { D1Database, Env } from "../worker/src/types.ts";

const fetchSpy = vi.spyOn(globalThis, "fetch");
let db: Awaited<ReturnType<typeof createMemoryD1>>;
let env: Env;
let ownerToken: string;
let memberToken: string;
let outsiderToken: string;
let teamId: string;

beforeAll(async () => {
  await setupTestKeys();
  fetchSpy.mockImplementation(testKeyFetcher);
});

afterEach(() => { db?.close(); });

async function request(path: string, token: string, method = "GET", body?: unknown, headers: Record<string, string> = {}) {
  const request = new Request(`https://taskpulse.test${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, ...(body === undefined ? {} : { "Content-Type": "application/json" }), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return worker.fetch(request, env, { waitUntil() {} });
}

async function postJson<T>(path: string, token: string, body: unknown, headers: Record<string, string> = {}) {
  const response = await request(path, token, "POST", body, headers);
  return { response, body: await response.json() as T };
}

describe("team and task API isolation", () => {
  it("creates a team, joins a second account, assigns a task, and enforces membership", async () => {
    db = await createMemoryD1();
    env = { DB: db as unknown as D1Database, FIREBASE_PROJECT_ID: testProjectId };
    ownerToken = await makeFirebaseTestToken({ sub: "owner", user_id: "owner", email: "owner@example.test", name: "Owner" });
    memberToken = await makeFirebaseTestToken({ sub: "member", user_id: "member", email: "member@example.test", name: "Member" });
    outsiderToken = await makeFirebaseTestToken({ sub: "outsider", user_id: "outsider", email: "outsider@example.test", name: "Outsider" });

    await request("/v1/me", ownerToken);
    const created = await postJson<{ team: { id: string } }>("/v1/teams", ownerToken, { name: "فريق التصميم" });
    expect(created.response.status).toBe(201);
    teamId = created.body.team.id;

    const dashboardBeforeJoin = await request(`/v1/teams/${teamId}/dashboard`, ownerToken);
    const dashboardEtagBeforeJoin = dashboardBeforeJoin.headers.get("etag");

    const invitation = await postJson<{ code: string }>(`/v1/teams/${teamId}/invitations`, ownerToken, { maxUses: 1, expiresInDays: 1 });
    expect(invitation.response.status).toBe(201);
    await request("/v1/me", memberToken);
    const joined = await postJson<{ teamId: string }>("/v1/teams/join", memberToken, { code: invitation.body.code });
    expect(joined.response.status).toBe(201);
    expect(joined.body.teamId).toBe(teamId);
    const secondUse = await postJson<{ error: { code: string } }>("/v1/teams/join", outsiderToken, { code: invitation.body.code });
    expect(secondUse.response.status).toBe(404);
    expect(secondUse.body.error.code).toBe("INVITATION_INVALID");

    const dashboardAfterJoin = await request(`/v1/teams/${teamId}/dashboard`, ownerToken, "GET", undefined,
      dashboardEtagBeforeJoin ? { "If-None-Match": dashboardEtagBeforeJoin } : {});
    expect(dashboardAfterJoin.status).toBe(200);

    const createdTask = await postJson<{ task: { id: string; dueAt: string; assignedTo: string; version: number } }>(
      `/v1/teams/${teamId}/tasks`, ownerToken,
      { title: "تصميم الموقع", description: "الصفحة الرئيسية", durationMinutes: 240, assignedTo: "member", priority: "high" },
      { "Idempotency-Key": "task-create-0001" },
    );
    expect(createdTask.response.status).toBe(201);
    expect(createdTask.body.task.assignedTo).toBe("member");
    expect(Date.parse(createdTask.body.task.dueAt) - Date.now()).toBeGreaterThan(239 * 60_000);

    const ownerTasks = await request(`/v1/teams/${teamId}/tasks`, ownerToken);
    const memberTasks = await request(`/v1/teams/${teamId}/tasks`, memberToken);
    expect((await ownerTasks.json() as { items: unknown[] }).items).toHaveLength(1);
    expect((await memberTasks.json() as { items: unknown[] }).items).toHaveLength(1);

    const outsider = await request(`/v1/teams/${teamId}/tasks`, outsiderToken);
    expect(outsider.status).toBe(404);
    expect((await outsider.json() as { error: { code: string } }).error.code).toBe("TEAM_NOT_FOUND");

    const dashboard = await request(`/v1/teams/${teamId}/dashboard`, memberToken);
    const dashboardEtag = dashboard.headers.get("etag");
    expect(dashboardEtag).toBeTruthy();
    const unchanged = await request(`/v1/teams/${teamId}/dashboard`, memberToken, "GET", undefined, { "If-None-Match": dashboardEtag! });
    expect(unchanged.status).toBe(304);
  });

  it("makes task creation idempotent and rejects changed payloads on key reuse", async () => {
    db = await createMemoryD1();
    env = { DB: db as unknown as D1Database, FIREBASE_PROJECT_ID: testProjectId };
    ownerToken = await makeFirebaseTestToken({ sub: "owner-2", user_id: "owner-2", email: "owner2@example.test", name: "Owner" });
    await request("/v1/me", ownerToken);
    const created = await postJson<{ team: { id: string } }>("/v1/teams", ownerToken, { name: "Team" });
    const path = `/v1/teams/${created.body.team.id}/tasks`;
    const first = await postJson<{ task: { id: string } }>(path, ownerToken, { title: "Prepare report", durationMinutes: 60 }, { "Idempotency-Key": "retry-key-0001" });
    const retry = await postJson<{ task: { id: string } }>(path, ownerToken, { title: "Prepare report", durationMinutes: 60 }, { "Idempotency-Key": "retry-key-0001" });
    expect(first.body.task.id).toBe(retry.body.task.id);
    const conflict = await postJson<{ error: { code: string } }>(path, ownerToken, { title: "Changed report", durationMinutes: 60 }, { "Idempotency-Key": "retry-key-0001" });
    expect(conflict.response.status).toBe(409);
    expect(conflict.body.error.code).toBe("IDEMPOTENCY_KEY_REUSED");
    const count = await db.prepare("SELECT COUNT(*) AS count FROM tasks").first<{ count: number }>();
    expect(count?.count).toBe(1);
  });

  it("serializes concurrent task edits with optimistic version checks", async () => {
    db = await createMemoryD1();
    env = { DB: db as unknown as D1Database, FIREBASE_PROJECT_ID: testProjectId };
    ownerToken = await makeFirebaseTestToken({ sub: "race-owner", user_id: "race-owner", email: "race@example.test", name: "Owner" });
    await request("/v1/me", ownerToken);
    const team = await postJson<{ team: { id: string } }>("/v1/teams", ownerToken, { name: "Race Team" });
    const created = await postJson<{ task: { id: string; version: number } }>(
      `/v1/teams/${team.body.team.id}/tasks`, ownerToken, { title: "Original", durationMinutes: 240 }, { "Idempotency-Key": "version-race-0001" },
    );
    const taskPath = `/v1/tasks/${created.body.task.id}`;
    const [first, second] = await Promise.all([
      request(taskPath, ownerToken, "PATCH", { expectedVersion: 1, title: "Edit A" }),
      request(taskPath, ownerToken, "PATCH", { expectedVersion: 1, title: "Edit B" }),
    ]);
    expect([first.status, second.status].sort()).toEqual([200, 409]);
    const conflict = first.status === 409 ? first : second;
    expect((await conflict.json() as { error: { code: string } }).error.code).toBe("VERSION_CONFLICT");
    const finalTask = await request(taskPath, ownerToken);
    expect((await finalTask.json() as { task: { version: number; title: string } }).task).toMatchObject({ version: 2 });
  });

  it("records completion before due time without creating an overdue event", async () => {
    db = await createMemoryD1();
    env = { DB: db as unknown as D1Database, FIREBASE_PROJECT_ID: testProjectId };
    ownerToken = await makeFirebaseTestToken({ sub: "owner-3", user_id: "owner-3", email: "owner3@example.test", name: "Owner" });
    await request("/v1/me", ownerToken);
    const team = await postJson<{ team: { id: string } }>("/v1/teams", ownerToken, { name: "Team" });
    const created = await postJson<{ task: { id: string; version: number } }>(
      `/v1/teams/${team.body.team.id}/tasks`, ownerToken, { title: "Review files", durationMinutes: 240 }, { "Idempotency-Key": "finish-before-due" },
    );
    const response = await request(`/v1/tasks/${created.body.task.id}/complete`, ownerToken, "POST", { expectedVersion: 1 });
    expect(response.status).toBe(200);
    await worker.scheduled({ cron: "* * * * *", scheduledTime: Date.now() + 5 * 60_000 }, env, { waitUntil() {} });
    const events = await db.prepare("SELECT COUNT(*) AS count FROM deadline_events WHERE kind = 'overdue'").first<{ count: number }>();
    expect(events?.count).toBe(0);
    const metrics = await db.prepare("SELECT completed_tasks FROM team_metrics WHERE team_id = ?").bind(team.body.team.id).first<{ completed_tasks: number }>();
    expect(metrics?.completed_tasks).toBe(1);
  });

  it("detects overdue work while the app is closed and repeated Cron runs stay idempotent", async () => {
    db = await createMemoryD1();
    env = { DB: db as unknown as D1Database, FIREBASE_PROJECT_ID: testProjectId };
    ownerToken = await makeFirebaseTestToken({ sub: "owner-4", user_id: "owner-4", email: "owner4@example.test", name: "Owner" });
    memberToken = await makeFirebaseTestToken({ sub: "member-4", user_id: "member-4", email: "member4@example.test", name: "Member" });
    await request("/v1/me", ownerToken);
    await request("/v1/me", memberToken);
    const team = await postJson<{ team: { id: string } }>("/v1/teams", ownerToken, { name: "Team" });
    const invitation = await postJson<{ code: string }>(`/v1/teams/${team.body.team.id}/invitations`, ownerToken, {});
    await postJson("/v1/teams/join", memberToken, { code: invitation.body.code });
    const created = await postJson<{ task: { id: string } }>(
      `/v1/teams/${team.body.team.id}/tasks`, ownerToken, { title: "Ship design", durationMinutes: 1, assignedTo: "member-4" }, { "Idempotency-Key": "one-minute-task" },
    );
    const due = await db.prepare("SELECT due_at FROM tasks WHERE id = ?").bind(created.body.task.id).first<{ due_at: string }>();
    const scheduledTime = Date.parse(due!.due_at) + 1000;
    const first = await (await import("../worker/src/scheduler.ts")).runScheduledWork(db, env, { cron: "* * * * *", scheduledTime }, async () => new Response("", { status: 503 }), scheduledTime);
    const second = await (await import("../worker/src/scheduler.ts")).runScheduledWork(db, env, { cron: "* * * * *", scheduledTime: scheduledTime + 60_000 }, async () => new Response("", { status: 503 }), scheduledTime + 60_000);
    expect(first.overdue).toBe(1);
    expect(second.overdue).toBe(0);
    const eventCount = await db.prepare("SELECT COUNT(*) AS count FROM deadline_events WHERE task_id = ? AND kind = 'overdue'").bind(created.body.task.id).first<{ count: number }>();
    const notificationCount = await db.prepare("SELECT COUNT(*) AS count FROM notifications WHERE task_id = ? AND type = 'overdue'").bind(created.body.task.id).first<{ count: number }>();
    const teamCount = await db.prepare("SELECT COUNT(*) AS count FROM team_members WHERE team_id = ? AND left_at IS NULL").bind(team.body.team.id).first<{ count: number }>();
    expect(eventCount?.count).toBe(1);
    expect(notificationCount?.count).toBe(teamCount?.count);
    const teamMetrics = await db.prepare("SELECT overdue_tasks FROM team_metrics WHERE team_id = ?").bind(team.body.team.id).first<{ overdue_tasks: number }>();
    const memberMetrics = await db.prepare("SELECT overdue_count FROM member_metrics WHERE team_id = ? AND user_id = 'member-4'").bind(team.body.team.id).first<{ overdue_count: number }>();
    expect(teamMetrics?.overdue_tasks).toBe(1);
    expect(memberMetrics?.overdue_count).toBe(1);
    const unread = await request("/v1/notifications?unread=true", memberToken);
    expect((await unread.json() as { items: Array<{ type: string; taskId: string }> }).items).toContainEqual(expect.objectContaining({ type: "overdue", taskId: created.body.task.id }));
  });

  it("sends the 30-minute reminder only to the assignee", async () => {
    db = await createMemoryD1();
    env = { DB: db as unknown as D1Database, FIREBASE_PROJECT_ID: testProjectId };
    ownerToken = await makeFirebaseTestToken({ sub: "reminder-owner", user_id: "reminder-owner", email: "owner@example.test", name: "Owner" });
    memberToken = await makeFirebaseTestToken({ sub: "reminder-member", user_id: "reminder-member", email: "member@example.test", name: "Assignee" });
    await request("/v1/me", ownerToken);
    await request("/v1/me", memberToken);
    const team = await postJson<{ team: { id: string } }>("/v1/teams", ownerToken, { name: "Reminder Team" });
    const invite = await postJson<{ code: string }>(`/v1/teams/${team.body.team.id}/invitations`, ownerToken, {});
    await postJson(`/v1/teams/join`, memberToken, { code: invite.body.code });
    const created = await postJson<{ task: { id: string } }>(
      `/v1/teams/${team.body.team.id}/tasks`, ownerToken,
      { title: "Review proposal", durationMinutes: 31, assignedTo: "reminder-member" },
      { "Idempotency-Key": "assignee-reminder" },
    );
    const task = await db.prepare("SELECT reminder_at FROM tasks WHERE id = ?").bind(created.body.task.id).first<{ reminder_at: string }>();
    const scheduledTime = Date.parse(task!.reminder_at!) + 1000;
    const { runScheduledWork } = await import("../worker/src/scheduler.ts");
    const result = await runScheduledWork(db, env, { cron: "* * * * *", scheduledTime }, async () => new Response("", { status: 503 }), scheduledTime);
    expect(result.reminders).toBe(1);
    const reminders = await db.prepare("SELECT user_id FROM notifications WHERE task_id = ? AND type = 'reminder'").bind(created.body.task.id).all<{ user_id: string }>();
    expect(reminders.results).toEqual([{ user_id: "reminder-member" }]);
    const ownerNotifications = await request("/v1/notifications", ownerToken);
    expect((await ownerNotifications.json() as { items: Array<{ type: string }> }).items.some((n) => n.type === "reminder")).toBe(false);
    const memberNotifications = await request("/v1/notifications", memberToken);
    expect((await memberNotifications.json() as { items: Array<{ type: string; taskId: string }> }).items).toContainEqual(expect.objectContaining({ type: "reminder", taskId: created.body.task.id }));
  });

  it("does not fan out overdue alerts to members who left before delivery", async () => {
    db = await createMemoryD1();
    env = { DB: db as unknown as D1Database, FIREBASE_PROJECT_ID: testProjectId };
    ownerToken = await makeFirebaseTestToken({ sub: "fanout-owner", user_id: "fanout-owner", email: "owner@example.test", name: "Owner" });
    memberToken = await makeFirebaseTestToken({ sub: "fanout-member", user_id: "fanout-member", email: "member@example.test", name: "Member" });
    await request("/v1/me", ownerToken);
    await request("/v1/me", memberToken);
    const team = await postJson<{ team: { id: string } }>("/v1/teams", ownerToken, { name: "Team" });
    const invitation = await postJson<{ code: string }>(`/v1/teams/${team.body.team.id}/invitations`, ownerToken, {});
    await postJson("/v1/teams/join", memberToken, { code: invitation.body.code });
    const eventAt = Date.now();
    const deliveryAt = eventAt + 60_000;
    await db.prepare("UPDATE team_members SET left_at = ? WHERE team_id = ? AND user_id = ?")
      .bind(new Date(eventAt + 10_000).toISOString(), team.body.team.id, "fanout-member").run();
    await db.prepare(`INSERT INTO notification_fanout (id, event_key, team_id, kind, title, body, created_at)
      VALUES ('fanout-test', 'overdue:fanout-test', ?, 'overdue', 'تنبيه Taskaty', 'مهمة متأخرة', ?)`)
      .bind(team.body.team.id, new Date(eventAt).toISOString()).run();

    const { runScheduledWork } = await import("../worker/src/scheduler.ts");
    await runScheduledWork(db, env, { cron: "* * * * *", scheduledTime: deliveryAt }, async () => new Response("", { status: 503 }), deliveryAt);
    const rows = await db.prepare("SELECT user_id FROM notifications WHERE event_key = 'overdue:fanout-test' ORDER BY user_id").all<{ user_id: string }>();
    expect(rows.results).toEqual([{ user_id: "fanout-owner" }]);
  });
});
