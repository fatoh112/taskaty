import { nowIso, randomId } from "./http.ts";
import { claimOutboxStatement, dispatchOutbox, type ClaimedOutboxRow } from "./fcm.ts";
import type { D1Database, D1PreparedStatement, Env, ScheduledController } from "./types.ts";

const MAX_DEADLINES_PER_KIND = 5;
const MAX_FANOUT_JOBS = 3;
const MAX_FANOUT_RECIPIENTS = 30;

interface DeadlineCandidate {
  id: string;
  team_id: string;
  title: string;
  created_by: string;
  assigned_to: string | null;
  assigned_name: string | null;
  due_at: string;
  reminder_at: string | null;
}
interface FanoutJob {
  id: string;
  event_key: string;
  team_id: string;
  task_id: string | null;
  kind: "overdue" | "completion";
  title: string;
  body: string;
  created_at: string;
  cursor_user_id: string;
  lease_until: string | null;
}

function deadlineStatements(candidate: DeadlineCandidate, kind: "reminder" | "overdue", now: number, db: D1Database) {
  const timestamp = nowIso(now);
  const eventKey = `${kind}:${candidate.id}`;
  const isOverdue = kind === "overdue";
  const taskUpdate = isOverdue
    ? db.prepare(`UPDATE tasks SET is_overdue = 1, overdue_alert_at = ?, updated_at = ?, version = version + 1
        WHERE id = ? AND is_overdue = 0 AND status IN ('pending', 'in_progress') AND due_at < ? RETURNING id`)
      .bind(timestamp, timestamp, candidate.id, timestamp)
    : db.prepare(`UPDATE tasks SET reminder_sent_at = ?, updated_at = ?, version = version + 1
        WHERE id = ? AND reminder_sent_at IS NULL AND status IN ('pending', 'in_progress') AND due_at > ? AND reminder_at <= ? RETURNING id`)
      .bind(timestamp, timestamp, candidate.id, timestamp, timestamp);
  const event = db.prepare(`INSERT INTO deadline_events (id, task_id, team_id, kind, occurred_at)
      SELECT ?, id, team_id, ?, ? FROM tasks WHERE id = ? AND ${isOverdue ? "overdue_alert_at" : "reminder_sent_at"} = ?
      ON CONFLICT(task_id, kind) DO NOTHING`)
    .bind(randomId(), kind, timestamp, candidate.id, timestamp);
  const safeTitle = candidate.title.slice(0, 150);
  const title = isOverdue ? "تنبيه Taskaty" : "تذكير Taskaty";
  const body = isOverdue
    ? candidate.assigned_name
      ? `${candidate.assigned_name.slice(0, 80)} لم يؤكد إنجاز مهمة ${safeTitle} قبل موعدها النهائي.`
      : `تجاوز موعد المهمة ${safeTitle} النهائي.`
    : `موعد مهمة ${safeTitle} قرب. راجع تفاصيلها في Taskaty.`;
  const statements = [taskUpdate, event];

  if (isOverdue) {
    // changes() here reads the preceding insert's row count. The unique event insert gates all metric increments.
    statements.push(db.prepare(`UPDATE team_metrics SET overdue_tasks = overdue_tasks + 1, revision = revision + 1, updated_at = ?
        WHERE changes() > 0 AND team_id = ? AND EXISTS (SELECT 1 FROM deadline_events WHERE task_id = ? AND kind = 'overdue')`)
      .bind(timestamp, candidate.team_id, candidate.id));
    statements.push(db.prepare(`UPDATE member_metrics SET overdue_count = overdue_count + 1, updated_at = ?
        WHERE changes() > 0 AND team_id = ? AND user_id = (SELECT assigned_to FROM tasks WHERE id = ?)
          AND EXISTS (SELECT 1 FROM deadline_events WHERE task_id = ? AND kind = 'overdue')`)
      .bind(timestamp, candidate.team_id, candidate.id, candidate.id));
    statements.push(db.prepare(`INSERT INTO notification_fanout (id, event_key, team_id, task_id, kind, title, body, created_at)
        SELECT ?, ?, team_id, id, 'overdue', ?, ?, ? FROM tasks WHERE id = ? AND overdue_alert_at = ?
        ON CONFLICT(event_key) DO NOTHING`)
      .bind(randomId(), eventKey, title, body, timestamp, candidate.id, timestamp));
  } else {
    statements.push(db.prepare(`INSERT INTO notifications (id, user_id, team_id, task_id, type, event_key, title, body, created_at)
        SELECT ?, assigned_to, team_id, id, 'reminder', ?, ?, ?, ? FROM tasks
        WHERE id = ? AND reminder_sent_at = ? AND assigned_to IS NOT NULL
        ON CONFLICT(user_id, event_key) DO NOTHING`)
      .bind(randomId(), eventKey, title, body, timestamp, candidate.id, timestamp));
    statements.push(db.prepare(`INSERT INTO notification_outbox (id, notification_id, recipient_user_id, task_id, status, available_at, created_at)
        SELECT ?, id, user_id, task_id, 'pending', ?, ? FROM notifications WHERE event_key = ?
        ON CONFLICT(notification_id, recipient_user_id) DO NOTHING`)
      .bind(randomId(), timestamp, timestamp, eventKey));
    statements.push(db.prepare(`UPDATE team_metrics SET revision = revision + 1, updated_at = ? WHERE team_id = ?
        AND EXISTS (SELECT 1 FROM deadline_events WHERE task_id = ? AND kind = 'reminder')`)
      .bind(timestamp, candidate.team_id, candidate.id));
  }

  statements.push(db.prepare(`INSERT INTO task_activity (id, task_id, team_id, actor_id, action, event_key, details_json, created_at)
      SELECT ?, t.id, t.team_id, t.created_by, ?, ?, '{}', ? FROM tasks t
      JOIN deadline_events e ON e.task_id = t.id AND e.kind = ?
      WHERE t.id = ? AND e.occurred_at = ?
      ON CONFLICT(task_id, event_key) WHERE event_key IS NOT NULL DO NOTHING`)
    .bind(randomId(), isOverdue ? "overdue" : "reminded", eventKey, timestamp, kind, candidate.id, timestamp));

  return statements;
}

function overdueCandidatesStatement(db: D1Database, timestamp: string) {
  return db.prepare(`SELECT id, team_id, title, created_by, assigned_to,
      (SELECT display_name FROM users WHERE uid = tasks.assigned_to) AS assigned_name, due_at, reminder_at
    FROM tasks WHERE is_overdue = 0 AND due_at < ? AND status IN ('pending', 'in_progress')
    ORDER BY due_at, id LIMIT ${MAX_DEADLINES_PER_KIND}`).bind(timestamp);
}

function reminderCandidatesStatement(db: D1Database, timestamp: string) {
  return db.prepare(`SELECT id, team_id, title, created_by, assigned_to,
      (SELECT display_name FROM users WHERE uid = tasks.assigned_to) AS assigned_name, due_at, reminder_at
    FROM tasks WHERE reminder_sent_at IS NULL AND reminder_at IS NOT NULL AND reminder_at <= ?
      AND due_at > ? AND status IN ('pending', 'in_progress') ORDER BY reminder_at, id LIMIT ${MAX_DEADLINES_PER_KIND}`)
    .bind(timestamp, timestamp);
}

async function processDeadlines(
  db: D1Database,
  overdueCandidates: DeadlineCandidate[],
  reminderCandidates: DeadlineCandidate[],
  now: number,
): Promise<{ overdue: number; reminders: number }> {
  const groups = [
    ...overdueCandidates.map((candidate) => ({ kind: "overdue" as const, statements: deadlineStatements(candidate, "overdue", now, db) })),
    ...reminderCandidates.map((candidate) => ({ kind: "reminder" as const, statements: deadlineStatements(candidate, "reminder", now, db) })),
  ];
  if (!groups.length) return { overdue: 0, reminders: 0 };

  const results = await db.batch(groups.flatMap((group) => group.statements));
  const processed = { overdue: 0, reminders: 0 };
  let resultOffset = 0;
  for (const group of groups) {
    if ((results[resultOffset]?.results?.length ?? 0) > 0) processed[group.kind === "overdue" ? "overdue" : "reminders"]++;
    resultOffset += group.statements.length;
  }
  return processed;
}

async function processFanout(db: D1Database, now: number): Promise<number> {
  const timestamp = nowIso(now);
  const leaseUntil = nowIso(now + 2 * 60_000);
  const claimed = await db.prepare(`UPDATE notification_fanout SET lease_until = ? WHERE id IN (
      SELECT id FROM notification_fanout WHERE completed_at IS NULL AND (lease_until IS NULL OR lease_until <= ?)
      ORDER BY created_at, id LIMIT ${MAX_FANOUT_JOBS}
    ) RETURNING id, event_key, team_id, task_id, kind, title, body, created_at, cursor_user_id, lease_until`)
    .bind(leaseUntil, timestamp).all<FanoutJob>();
  const jobs = claimed.results ?? [];
  if (!jobs.length) return 0;

  // Read each bounded member page in one D1 batch, then commit all claimed fanouts together.
  const memberPages = await db.batch<{ user_id: string }>(jobs.map((job) =>
    db.prepare(`SELECT user_id FROM team_members WHERE team_id = ? AND user_id > ? AND left_at IS NULL
        ORDER BY user_id LIMIT ${MAX_FANOUT_RECIPIENTS + 1}`)
      .bind(job.team_id, job.cursor_user_id),
  ));
  let processed = 0;
  const statements: D1PreparedStatement[] = [];
  for (const [jobIndex, job] of jobs.entries()) {
    const members = memberPages[jobIndex];
    const page = (members.results ?? []).slice(0, MAX_FANOUT_RECIPIENTS);
    const ids = page.map((row) => row.user_id);
    const lastUserId = ids[ids.length - 1];
    if (!lastUserId) {
      statements.push(db.prepare("UPDATE notification_fanout SET completed_at = ?, lease_until = NULL WHERE id = ? AND lease_until = ?")
        .bind(timestamp, job.id, job.lease_until));
      continue;
    }
    const recipients = "user_id > ? AND user_id <= ?";
    const insertNotifications = db.prepare(`INSERT INTO notifications (id, user_id, team_id, task_id, type, event_key, title, body, created_at)
        SELECT lower(hex(randomblob(16))), user_id, team_id, ?, ?, ?, ?, ?, ? FROM team_members
        WHERE team_id = ? AND ${recipients} AND left_at IS NULL
        ON CONFLICT(user_id, event_key) DO NOTHING`)
      .bind(job.task_id, job.kind, job.event_key, job.title, job.body, job.created_at, job.team_id, job.cursor_user_id, lastUserId);
    const insertOutbox = db.prepare(`INSERT INTO notification_outbox (id, notification_id, recipient_user_id, task_id, status, available_at, created_at)
        SELECT lower(hex(randomblob(16))), n.id, n.user_id, n.task_id, 'pending', ?, ? FROM notifications n
        WHERE n.team_id = ? AND n.event_key = ? AND n.created_at = ? AND n.user_id > ? AND n.user_id <= ?
        ON CONFLICT(notification_id, recipient_user_id) DO NOTHING`)
      .bind(timestamp, timestamp, job.team_id, job.event_key, job.created_at, job.cursor_user_id, lastUserId);
    const complete = (members.results?.length ?? 0) <= MAX_FANOUT_RECIPIENTS;
    const updateCursor = db.prepare(`UPDATE notification_fanout SET cursor_user_id = ?, lease_until = ?,
        completed_at = CASE WHEN ? = 1 THEN ? ELSE NULL END
      WHERE id = ? AND lease_until = ? AND completed_at IS NULL`)
      .bind(lastUserId, complete ? null : leaseUntil, complete ? 1 : 0, complete ? timestamp : null, job.id, job.lease_until);
    statements.push(insertNotifications, insertOutbox, updateCursor);
    processed += ids.length;
  }
  if (statements.length) await db.batch(statements);
  return processed;
}

export async function runScheduledWork(db: D1Database, env: Env, _controller: ScheduledController, fetcher: typeof fetch = fetch, now = Date.now()) {
  const timestamp = nowIso(now);
  try {
    // Start the heartbeat and read both indexed deadline queues in one D1 batch.
    const initial = await db.batch<DeadlineCandidate>([
      db.prepare(`INSERT INTO worker_heartbeats (name, last_started_at, overdue_processed, reminders_processed, fanout_processed, outbox_processed)
          VALUES ('taskpulse', ?, 0, 0, 0, 0) ON CONFLICT(name) DO UPDATE SET last_started_at = excluded.last_started_at,
          last_error_code = NULL, overdue_processed = 0, reminders_processed = 0, fanout_processed = 0, outbox_processed = 0`)
        .bind(timestamp),
      overdueCandidatesStatement(db, timestamp),
      reminderCandidatesStatement(db, timestamp),
    ]);
    const { overdue, reminders } = await processDeadlines(db, initial[1]?.results ?? [], initial[2]?.results ?? [], now);
    const fanout = await processFanout(db, now);
    let outbox = 0;
    let finishedWithoutDelivery = false;
    if (env.FCM_TOKEN_ENCRYPTION_KEY && env.FCM_SERVICE_ACCOUNT_JSON) {
      // When the outbox is empty, commit the finish heartbeat in the same batch as its claim.
      // If messages were claimed, defer that heartbeat until their delivery states are persisted.
      const deliveryBatch = await db.batch<ClaimedOutboxRow>([
        claimOutboxStatement(db, now),
        db.prepare(`UPDATE worker_heartbeats SET last_finished_at = ?, last_error_code = NULL,
            overdue_processed = ?, reminders_processed = ?, fanout_processed = ?, outbox_processed = 0
          WHERE name = 'taskpulse' AND changes() = 0`)
          .bind(nowIso(Date.now()), overdue, reminders, fanout),
      ]);
      const claimedRows = deliveryBatch[0]?.results ?? [];
      finishedWithoutDelivery = claimedRows.length === 0;
      outbox = await dispatchOutbox(db, env, fetcher, now, claimedRows);
    } else {
      outbox = await dispatchOutbox(db, env, fetcher, now);
    }
    if (!finishedWithoutDelivery) {
      await db.prepare(`UPDATE worker_heartbeats SET last_finished_at = ?, last_error_code = NULL,
          overdue_processed = ?, reminders_processed = ?, fanout_processed = ?, outbox_processed = ? WHERE name = 'taskpulse'`)
        .bind(nowIso(Date.now()), overdue, reminders, fanout, outbox).run();
    }
    return { overdue, reminders, fanoutRecipients: fanout, outbox };
  } catch (error) {
    const errorCode = error instanceof Error ? error.name.slice(0, 80) : "SCHEDULE_FAILED";
    await db.prepare(`INSERT INTO worker_heartbeats (name, last_started_at, last_error_code)
        VALUES ('taskpulse', ?, ?) ON CONFLICT(name) DO UPDATE SET last_started_at = excluded.last_started_at,
        last_error_code = excluded.last_error_code`)
      .bind(timestamp, errorCode).run();
    throw error;
  }
}

export { MAX_DEADLINES_PER_KIND, MAX_FANOUT_JOBS, MAX_FANOUT_RECIPIENTS };
