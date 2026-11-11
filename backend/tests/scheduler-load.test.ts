import { afterEach, beforeAll, describe, expect, it } from "vitest";
import { createMemoryD1 } from "./support/memory-d1.ts";
import { encodeBase64, nowIso } from "../worker/src/http.ts";
import { registerDevice, resetDeviceEncryptionKeyForTests } from "../worker/src/notifications.ts";
import { resetFcmTokenCacheForTests } from "../worker/src/fcm.ts";
import { runScheduledWork } from "../worker/src/scheduler.ts";
import { updateTask } from "../worker/src/tasks.ts";
import type { D1Database, D1PreparedStatement, D1Result, Env } from "../worker/src/types.ts";

interface Metrics {
  directRequests: number;
  batchRequests: number;
  sqlStatements: number;
  rowsReturned: number;
  rowsChanged: number;
  sqlExecutionMs: number;
}

class CountedStatement implements D1PreparedStatement {
  private batched = false;
  constructor(private readonly inner: D1PreparedStatement, private readonly metrics: Metrics) {}
  markBatched() { this.batched = true; }
  bind(...values: unknown[]): D1PreparedStatement { this.inner.bind(...values); return this; }
  private started() {
    if (!this.batched) this.metrics.directRequests++;
    this.metrics.sqlStatements++;
    return performance.now();
  }
  private finished(result: D1Result<unknown>, started: number) {
    this.metrics.rowsReturned += result.results?.length ?? 0;
    this.metrics.rowsChanged += result.meta?.changes ?? 0;
    this.metrics.sqlExecutionMs += performance.now() - started;
  }
  async first<T = Record<string, unknown>>(columnName?: string): Promise<T | null> {
    const started = this.started();
    const row = await this.inner.first<T>(columnName);
    this.metrics.rowsReturned += row == null ? 0 : 1;
    this.metrics.sqlExecutionMs += performance.now() - started;
    return row;
  }
  async all<T = Record<string, unknown>>(): Promise<D1Result<T>> {
    const started = this.started();
    const result = await this.inner.all<T>();
    this.finished(result as D1Result<unknown>, started);
    return result;
  }
  async run<T = Record<string, unknown>>(): Promise<D1Result<T>> {
    const started = this.started();
    const result = await this.inner.run<T>();
    this.finished(result as D1Result<unknown>, started);
    return result;
  }
}

class CountedD1 implements D1Database {
  readonly metrics: Metrics = { directRequests: 0, batchRequests: 0, sqlStatements: 0, rowsReturned: 0, rowsChanged: 0, sqlExecutionMs: 0 };
  constructor(private readonly inner: D1Database) {}
  prepare(query: string): D1PreparedStatement { return new CountedStatement(this.inner.prepare(query), this.metrics); }
  batch<T = unknown>(statements: D1PreparedStatement[]): Promise<D1Result<T>[]> {
    this.metrics.batchRequests++;
    for (const statement of statements) (statement as CountedStatement).markBatched();
    return this.inner.batch(statements);
  }
  get requests() { return this.metrics.directRequests + this.metrics.batchRequests; }
}

interface Fixture {
  rawDb: Awaited<ReturnType<typeof createMemoryD1>>;
  db: CountedD1;
  env: Env;
  baseTime: number;
  taskIds: string[];
  userIds: string[];
  encryptionSecret: string;
}

let serviceAccountJson: string;
const projectId = "taskpulse-load-test";
const id = (prefix: string, n: number) => `${prefix}-${String(n).padStart(3, "0")}`;
const tokenFor = (userId: string, device: number) => `taskaty-${userId}-device-${device}-${"x".repeat(48)}`;
const percentiles = (values: number[]) => {
  const sorted = [...values].sort((a, b) => a - b);
  const at = (p: number) => sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * p) - 1)] ?? 0;
  return { p50: at(0.5), p95: at(0.95), max: sorted.at(-1) ?? 0 };
};
const statusCounts = async (db: Awaited<ReturnType<typeof createMemoryD1>>) => {
  const result = await db.prepare("SELECT status, COUNT(*) AS count FROM notification_outbox GROUP BY status").all<{ status: string; count: number }>();
  return Object.fromEntries((result.results ?? []).map((row) => [row.status, row.count]));
};

async function createFixture(taskCount: number, memberCount: number, baseTime: number, dueAt: number): Promise<Fixture> {
  const rawDb = await createMemoryD1();
  const db = new CountedD1(rawDb);
  const encryptionSecret = encodeBase64(crypto.getRandomValues(new Uint8Array(32)));
  const env: Env = { DB: db, FIREBASE_PROJECT_ID: projectId, FCM_SERVICE_ACCOUNT_JSON: serviceAccountJson, FCM_TOKEN_ENCRYPTION_KEY: encryptionSecret };
  const createdAt = nowIso(baseTime - 4 * 60 * 60_000);
  const userIds = Array.from({ length: memberCount }, (_, i) => id("user", i));
  const taskIds = Array.from({ length: taskCount }, (_, i) => id("task", i));

  for (let i = 0; i < memberCount; i++) {
    const userId = userIds[i]!;
    await rawDb.prepare("INSERT INTO users (uid,email,display_name,created_at,updated_at) VALUES (?,?,?,?,?)")
      .bind(userId, `${userId}@example.test`, `Member ${i}`, createdAt, createdAt).run();
  }
  await rawDb.prepare("INSERT INTO teams (id,name,owner_id,created_at,updated_at) VALUES ('load-team','Load team',?,?,?)")
    .bind(userIds[0]!, createdAt, createdAt).run();
  for (let i = 0; i < memberCount; i++) {
    await rawDb.prepare("INSERT INTO team_members (team_id,user_id,role,joined_at) VALUES ('load-team',?,?,?)")
      .bind(userIds[i]!, i === 0 ? "owner" : "member", createdAt).run();
    await rawDb.prepare("INSERT INTO member_metrics (team_id,user_id,updated_at) VALUES ('load-team',?,?)")
      .bind(userIds[i]!, createdAt).run();
  }
  await rawDb.prepare("INSERT INTO team_metrics (team_id,updated_at) VALUES ('load-team',?)").bind(createdAt).run();
  for (let i = 0; i < taskCount; i++) {
    await rawDb.prepare(`INSERT INTO tasks (id,team_id,title,created_by,assigned_to,created_at,updated_at,duration_minutes,due_at)
      VALUES (?,'load-team',?,?,?, ?,?,60,?)`).bind(
      taskIds[i]!, `Load task ${i}`, userIds[0]!, userIds[i % memberCount]!, createdAt, createdAt, nowIso(dueAt),
    ).run();
  }
  return { rawDb, db, env, baseTime, taskIds, userIds, encryptionSecret };
}

async function registerDevices(fixture: Fixture, devicesPerMember: number) {
  for (const userId of fixture.userIds) {
    for (let device = 0; device < devicesPerMember; device++) {
      await registerDevice(fixture.rawDb, userId, { token: tokenFor(userId, device), platform: "android" }, fixture.encryptionSecret, fixture.baseTime);
    }
  }
}

function serviceAccountFixture(): Promise<string> {
  return crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"])
    .then(async (pair) => {
      const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
      const pemBody = encodeBase64(pkcs8).match(/.{1,64}/g)!.join("\n");
      return JSON.stringify({ type: "service_account", project_id: projectId, client_email: `worker@${projectId}.iam.gserviceaccount.com`, private_key: `-----BEGIN PRIVATE KEY-----\n${pemBody}\n-----END PRIVATE KEY-----\n` });
    });
}

beforeAll(async () => { serviceAccountJson = await serviceAccountFixture(); });
afterEach(() => { resetFcmTokenCacheForTests(); resetDeviceEncryptionKeyForTests(); });

describe("bounded scheduler load", () => {
  it("handles 10 simultaneous deadlines, 30 members, two devices, retry, and duplicate Cron calls", async () => {
    const baseTime = Math.floor(Date.now() / 60_000) * 60_000;
    const fixture = await createFixture(10, 30, baseTime, baseTime - 60_000);
    await registerDevices(fixture, 2);
    const transientToken = tokenFor("user-000", 0);
    const attemptsByToken = new Map<string, number>();
    let externalRequests = 0;
    const fetcher: typeof fetch = async (input, init) => {
      externalRequests++;
      const url = String(input);
      if (url === "https://oauth2.googleapis.com/token") return new Response(JSON.stringify({ access_token: "load-test-token", expires_in: 3600 }), { status: 200 });
      if (!url.includes("fcm.googleapis.com")) throw new Error("Unexpected mock URL");
      const payload = JSON.parse(String(init?.body)) as { message: { token: string } };
      const token = payload.message.token;
      const attempts = (attemptsByToken.get(token) ?? 0) + 1;
      attemptsByToken.set(token, attempts);
      if (token === transientToken && attempts === 1) return new Response(JSON.stringify({ error: { status: "UNAVAILABLE" } }), { status: 503 });
      return new Response(JSON.stringify({ name: `projects/${projectId}/messages/mock` }), { status: 200 });
    };

    const tickWallMs: number[] = [];
    const tickCpuMs: number[] = [];
    let peakSubrequests = 0;
    let completedTicks = 0;
    for (let tick = 0; tick < 45; tick++) {
      const at = baseTime + tick * 60_000;
      const beforeRequests = fixture.db.requests;
      const beforeExternal = externalRequests;
      const beforeCpu = process.cpuUsage();
      const started = performance.now();
      await runScheduledWork(fixture.db, fixture.env, { cron: "* * * * *", scheduledTime: at }, fetcher, at);
      tickWallMs.push(performance.now() - started);
      const cpu = process.cpuUsage(beforeCpu);
      tickCpuMs.push((cpu.user + cpu.system) / 1000);
      peakSubrequests = Math.max(peakSubrequests, fixture.db.requests - beforeRequests + externalRequests - beforeExternal);
      completedTicks = tick + 1;
      const statuses = await statusCounts(fixture.rawDb);
      if ((statuses.sent ?? 0) === 300) break;
    }

    const events = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM deadline_events WHERE kind='overdue'").first<{ count: number }>();
    const notificationCount = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM notifications WHERE type='overdue'").first<{ count: number }>();
    const fanout = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM notification_fanout WHERE completed_at IS NOT NULL").first<{ count: number }>();
    const statuses = await statusCounts(fixture.rawDb);
    expect(completedTicks).toBeLessThan(45);
    expect(events?.count).toBe(10);
    expect(notificationCount?.count).toBe(300);
    expect(fanout?.count).toBe(10);
    expect(statuses.sent).toBe(300);
    expect(attemptsByToken.size).toBe(60);
    expect([...attemptsByToken.values()].every((count) => count >= 10)).toBe(true);
    expect(attemptsByToken.get(transientToken)).toBe(11);
    expect(peakSubrequests).toBeLessThanOrEqual(50);

    const beforeRepeated = { events: events?.count, notifications: notificationCount?.count };
    await runScheduledWork(fixture.db, fixture.env, { cron: "* * * * *", scheduledTime: baseTime + (completedTicks - 1) * 60_000 }, fetcher, baseTime + (completedTicks - 1) * 60_000);
    const afterRepeatedEvents = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM deadline_events WHERE kind='overdue'").first<{ count: number }>();
    const afterRepeatedNotifications = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM notifications WHERE type='overdue'").first<{ count: number }>();
    expect({ events: afterRepeatedEvents?.count, notifications: afterRepeatedNotifications?.count }).toEqual(beforeRepeated);

    const measurements = {
      scenario: "10 overdue tasks; 30 team members; 2 devices/member; one transient FCM 503",
      cronTicksToDrain: completedTicks,
      overdueDetectionLatencyMinutes: percentiles((await fixture.rawDb.prepare("SELECT e.occurred_at, t.due_at FROM deadline_events e JOIN tasks t ON t.id=e.task_id WHERE e.kind='overdue'").all<{ occurred_at: string; due_at: string }>()).results!.map((row) => (Date.parse(row.occurred_at) - Date.parse(row.due_at)) / 60_000)),
      notificationFanoutRows: notificationCount?.count,
      outboxStatusCounts: statuses,
      fcmFetchCountIncludingOAuth: externalRequests,
      transientTokenAttemptCount: attemptsByToken.get(transientToken),
      d1Requests: fixture.db.requests,
      d1SqlStatements: fixture.db.metrics.sqlStatements,
      d1RowsReturned: fixture.db.metrics.rowsReturned,
      d1RowsChanged: fixture.db.metrics.rowsChanged,
      d1AdapterSqlWallMs: Number(fixture.db.metrics.sqlExecutionMs.toFixed(2)),
      testHarnessWallMs: percentiles(tickWallMs),
      nodeProcessCpuMs: percentiles(tickCpuMs),
      cloudflareWorkerCpuMs: "not exposed by SQL.js/Node harness; requires Cloudflare runtime telemetry",
      maximumObservedCombinedSubrequests: peakSubrequests,
    };
    console.info(`TASKPULSE_SCHEDULER_LOAD ${JSON.stringify(measurements)}`);
    fixture.rawDb.close();
  }, 60_000);

  it("drains 100 overdue tasks after a 10-minute outage without exceeding the 50-subrequest envelope", async () => {
    const baseTime = Math.floor(Date.now() / 60_000) * 60_000;
    const fixture = await createFixture(100, 30, baseTime, baseTime - 10 * 60_000);
    await registerDevices(fixture, 2);
    const attemptsByToken = new Map<string, number>();
    const transientToken = tokenFor('user-000', 0);
    let externalRequests = 0;
    const fetcher: typeof fetch = async (input, init) => {
      externalRequests++;
      const url = String(input);
      if (url === 'https://oauth2.googleapis.com/token') {
        return new Response(JSON.stringify({ access_token: 'load-test-token', expires_in: 3600 }), { status: 200 });
      }
      if (!url.includes('fcm.googleapis.com')) throw new Error('Unexpected mock URL');
      const payload = JSON.parse(String(init?.body)) as { message: { token: string } };
      const token = payload.message.token;
      const attempts = (attemptsByToken.get(token) ?? 0) + 1;
      attemptsByToken.set(token, attempts);
      if (token === transientToken && attempts === 1) {
        return new Response(JSON.stringify({ error: { status: 'UNAVAILABLE' } }), { status: 503 });
      }
      return new Response(JSON.stringify({ name: `projects/${projectId}/messages/mock` }), { status: 200 });
    };
    let peakSubrequests = 0;
    const tickWallMs: number[] = [];
    const tickCpuMs: number[] = [];
    let completedTicks = 0;
    for (let tick = 0; tick < 220; tick++) {
      const at = baseTime + tick * 60_000;
      const beforeRequests = fixture.db.requests;
      const beforeExternal = externalRequests;
      const beforeCpu = process.cpuUsage();
      const started = performance.now();
      await runScheduledWork(fixture.db, fixture.env, { cron: "* * * * *", scheduledTime: at }, fetcher, at);
      tickWallMs.push(performance.now() - started);
      const cpu = process.cpuUsage(beforeCpu);
      tickCpuMs.push((cpu.user + cpu.system) / 1000);
      peakSubrequests = Math.max(peakSubrequests, fixture.db.requests - beforeRequests + externalRequests - beforeExternal);
      completedTicks = tick + 1;
      const statuses = await statusCounts(fixture.rawDb);
      if ((statuses.sent ?? 0) === 3000) break;
    }

    const events = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM deadline_events WHERE kind='overdue'").first<{ count: number }>();
    const notifications = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM notifications WHERE type='overdue'").first<{ count: number }>();
    const maxDetection = await fixture.rawDb.prepare("SELECT MAX((julianday(e.occurred_at)-julianday(t.due_at))*1440) AS minutes FROM deadline_events e JOIN tasks t ON t.id=e.task_id WHERE e.kind='overdue'").first<{ minutes: number }>();
    const maxFanoutDelay = await fixture.rawDb.prepare(`SELECT MAX((julianday(n.created_at)-julianday(e.occurred_at))*1440) AS minutes
      FROM notifications n JOIN deadline_events e ON e.task_id=n.task_id AND e.kind='overdue'`).first<{ minutes: number }>();
    const statuses = await statusCounts(fixture.rawDb);
    expect(completedTicks).toBeLessThanOrEqual(220);
    expect(events?.count).toBe(100);
    expect(notifications?.count).toBe(3000);
    expect(statuses.sent).toBe(3000);
    expect(attemptsByToken.size).toBe(60);
    expect(attemptsByToken.get(transientToken)).toBe(101);
    expect(maxDetection?.minutes).toBeLessThanOrEqual(30.01);
    expect(maxFanoutDelay?.minutes).toBeLessThanOrEqual(15.01);
    expect(peakSubrequests).toBeLessThanOrEqual(50);

    const measurements = {
      scenario: "100 overdue tasks accumulated during a 10-minute outage; 30 members; 2 devices/member; one transient FCM 503",
      cronTicksToDrainPersistentOutbox: completedTicks,
      detectionMinutesFromOutageRecovery: 20,
      maximumDeadlineToDetectionMinutes: Number((maxDetection?.minutes ?? 0).toFixed(2)),
      maximumEventToPersistentFanoutMinutes: Number((maxFanoutDelay?.minutes ?? 0).toFixed(2)),
      persistentNotificationRows: notifications?.count,
      outboxStatusCounts: statuses,
      estimatedFcmDrainTicksAt15RecipientsPerTick: Math.ceil(3000 / 15),
      fcmFetchCountIncludingOAuth: externalRequests,
      transientTokenAttemptCount: attemptsByToken.get(transientToken),
      d1Requests: fixture.db.requests,
      d1SqlStatements: fixture.db.metrics.sqlStatements,
      d1RowsReturned: fixture.db.metrics.rowsReturned,
      d1RowsChanged: fixture.db.metrics.rowsChanged,
      d1AdapterSqlWallMs: Number(fixture.db.metrics.sqlExecutionMs.toFixed(2)),
      testHarnessWallMs: percentiles(tickWallMs),
      nodeProcessCpuMs: percentiles(tickCpuMs),
      cloudflareWorkerCpuMs: "not exposed by SQL.js/Node harness; requires Cloudflare runtime telemetry",
      maximumObservedCombinedSubrequests: peakSubrequests,
      realFcmLatency: "not measured; FCM responses are mocked",
    };
    console.info(`TASKPULSE_SCHEDULER_LOAD ${JSON.stringify(measurements)}`);
    fixture.rawDb.close();
  }, 60_000);

  it("does not alert when task completion and Cron meet exactly at the deadline", async () => {
    const deadline = Math.floor(Date.now() / 60_000) * 60_000;
    const fixture = await createFixture(1, 1, deadline, deadline);
    const taskId = fixture.taskIds[0]!;
    const [completed, scheduled] = await Promise.all([
      updateTask(fixture.db, taskId, fixture.userIds[0]!, { expectedVersion: 1, status: "completed" }, deadline),
      runScheduledWork(fixture.db, fixture.env, { cron: "* * * * *", scheduledTime: deadline }, async () => new Response("", { status: 503 }), deadline),
    ]);
    const task = await fixture.rawDb.prepare("SELECT status, completed_at FROM tasks WHERE id=?").bind(taskId).first<{ status: string; completed_at: string | null }>();
    const events = await fixture.rawDb.prepare("SELECT COUNT(*) AS count FROM deadline_events WHERE task_id=? AND kind='overdue'").bind(taskId).first<{ count: number }>();
    expect(completed.status).toBe("completed");
    expect(task?.completed_at).toBe(nowIso(deadline));
    expect(scheduled.overdue).toBe(0);
    expect(events?.count).toBe(0);
    fixture.rawDb.close();
  });
});
