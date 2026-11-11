import { ApiError, optionalString, randomId, requireInteger, requireString, sha256Hex, nowIso } from "./http.ts";
import { decodeCursor, encodeCursor, getMembership, requireRole } from "./data.ts";
import type { AuthUser, D1Database, TaskRow } from "./types.ts";

const ACTIVE_STATUSES = ["pending", "in_progress"] as const;

function publicTask(row: TaskRow) {
  return {
    id: row.id,
    teamId: row.team_id,
    title: row.title,
    description: row.description,
    createdBy: row.created_by,
    assignedTo: row.assigned_to,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    durationMinutes: row.duration_minutes,
    dueAt: row.due_at,
    reminderAt: row.reminder_at,
    reminderSentAt: row.reminder_sent_at,
    priority: row.priority,
    status: row.status,
    completedAt: row.completed_at,
    isOverdue: row.is_overdue === 1,
    overdueAlertAt: row.overdue_alert_at,
    version: row.version,
  };
}

function parseTask(row: TaskRow | null): TaskRow {
  if (!row) throw new ApiError("TASK_NOT_FOUND", 404, "Task was not found.");
  return row;
}

export async function listTasks(
  db: D1Database,
  teamId: string,
  userId: string,
  query: URLSearchParams,
  now = Date.now(),
) {
  await getMembership(db, teamId, userId);
  const limit = Math.max(1, Math.min(100, Number.parseInt(query.get("limit") ?? "30", 10) || 30));
  const cursor = decodeCursor(query.get("cursor"));
  const where = ["team_id = ?"];
  const parameters: unknown[] = [teamId];
  const status = query.get("status");
  if (status) {
    if (!(["pending", "in_progress", "completed", "cancelled"] as string[]).includes(status)) {
      throw new ApiError("INVALID_FILTER", 400);
    }
    where.push("status = ?");
    parameters.push(status);
  }
  const assignee = query.get("assignedTo");
  if (assignee === "me") {
    where.push("assigned_to = ?");
    parameters.push(userId);
  } else if (assignee) {
    await getMembership(db, teamId, assignee);
    where.push("assigned_to = ?");
    parameters.push(assignee);
  }
  if (query.get("overdue") === "true") where.push("is_overdue = 1");
  const search = query.get("q")?.trim();
  if (search) {
    if (search.length > 100) throw new ApiError("INVALID_FILTER", 400, "Search text is too long.");
    const prefix = search.replace(/[%_]/g, "");
    if (prefix) {
      where.push("title LIKE ? COLLATE NOCASE");
      parameters.push(`${prefix}%`);
    }
  }
  if (cursor) {
    where.push("(created_at < ? OR (created_at = ? AND id < ?))");
    parameters.push(cursor[0], cursor[0], cursor[1]);
  }
  parameters.push(limit + 1);
  const result = await db
    .prepare(
      `SELECT id, team_id, title, description, created_by, assigned_to, created_at, updated_at,
              duration_minutes, due_at, reminder_at, reminder_sent_at, priority, status,
              completed_at, is_overdue, overdue_alert_at, version
       FROM tasks WHERE ${where.join(" AND ")}
       ORDER BY created_at DESC, id DESC LIMIT ?`,
    )
    .bind(...parameters)
    .all<TaskRow>();
  const rows = result.results ?? [];
  const hasMore = rows.length > limit;
  const page = rows.slice(0, limit);
  const tail = page[page.length - 1];
  return {
    items: page.map(publicTask),
    nextCursor: hasMore && tail ? encodeCursor([tail.created_at, tail.id]) : null,
    serverTime: nowIso(now),
  };
}

export async function getTask(db: D1Database, taskId: string, userId: string) {
  const row = await db
    .prepare(
      `SELECT id, team_id, title, description, created_by, assigned_to, created_at, updated_at,
              duration_minutes, due_at, reminder_at, reminder_sent_at, priority, status,
              completed_at, is_overdue, overdue_alert_at, version
       FROM tasks WHERE id = ?`,
    )
    .bind(taskId)
    .first<TaskRow>();
  const task = parseTask(row);
  await getMembership(db, task.team_id, userId);
  return publicTask(task);
}

export async function getTaskActivity(db: D1Database, taskId: string, userId: string) {
  const task = await db.prepare("SELECT team_id FROM tasks WHERE id = ?").bind(taskId).first<{ team_id: string }>();
  if (!task) throw new ApiError("TASK_NOT_FOUND", 404);
  await getMembership(db, task.team_id, userId);
  const result = await db
    .prepare(
      `SELECT a.id, a.actor_id AS actorId, u.display_name AS actorName, a.action,
              a.details_json AS details, a.created_at AS createdAt
       FROM task_activity a JOIN users u ON u.uid = a.actor_id
       WHERE a.task_id = ? ORDER BY a.created_at DESC, a.id DESC LIMIT 100`,
    )
    .bind(taskId)
    .all();
  return result.results ?? [];
}

export async function createTask(
  db: D1Database,
  user: AuthUser,
  teamId: string,
  input: Record<string, unknown>,
  idempotencyKey: string | null,
  now = Date.now(),
) {
  await getMembership(db, teamId, user.uid);
  const title = requireString(input.title, "title", 1, 240);
  const description = optionalString(input.description, "description", 4000) ?? "";
  let durationMinutes = requireInteger(input.durationMinutes ?? 240, "durationMinutes", 1, 525600);
  let requestedDueAt: string | null = null;
  if (input.dueAt !== undefined && input.dueAt !== null) {
    const rawDueAt = requireString(input.dueAt, "dueAt", 20, 40);
    const parsedDueAt = Date.parse(rawDueAt);
    const delta = parsedDueAt - now;
    if (!Number.isFinite(parsedDueAt) || delta < 30_000 || delta > 525600 * 60_000) {
      throw new ApiError("INVALID_DEADLINE", 400, "Deadline must be at least 30 seconds ahead and within one year.");
    }
    requestedDueAt = nowIso(parsedDueAt);
    durationMinutes = Math.max(1, Math.ceil(delta / 60_000));
  }
  const priority = input.priority === undefined ? "normal" : input.priority;
  if (!(["low", "normal", "high", "urgent"] as unknown[]).includes(priority)) throw new ApiError("INVALID_INPUT", 400, "priority is invalid.");
  const assignedTo = input.assignedTo === undefined ? user.uid : optionalString(input.assignedTo, "assignedTo", 128);
  if (assignedTo) await getMembership(db, teamId, assignedTo);
  const key = idempotencyKey ?? (typeof input.idempotencyKey === "string" ? input.idempotencyKey : null);
  if (!key || !/^[A-Za-z0-9_-]{8,100}$/.test(key)) throw new ApiError("IDEMPOTENCY_KEY_REQUIRED", 400);

  const requestHash = await sha256Hex(JSON.stringify({ teamId, title, description, durationMinutes, dueAt: requestedDueAt, priority, assignedTo }));
  const prior = await db
    .prepare("SELECT id, request_hash FROM tasks WHERE created_by = ? AND idempotency_key = ?")
    .bind(user.uid, key)
    .first<{ id: string; request_hash: string | null }>();
  if (prior) {
    if (prior.request_hash !== requestHash) throw new ApiError("IDEMPOTENCY_KEY_REUSED", 409);
    return getTask(db, prior.id, user.uid);
  }

  const createdAt = nowIso(now);
  const dueAt = requestedDueAt ?? nowIso(now + durationMinutes * 60_000);
  const dueEpoch = Date.parse(dueAt);
  const reminderAt = dueEpoch - now > 30 * 60_000 ? nowIso(dueEpoch - 30 * 60_000) : null;
  const taskId = randomId();
  const statements = [
    db.prepare(
      `INSERT INTO tasks (id, team_id, title, description, created_by, assigned_to, created_at, updated_at,
       duration_minutes, due_at, reminder_at, priority, idempotency_key, request_hash)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(created_by, idempotency_key) DO NOTHING
       RETURNING id`,
    ).bind(taskId, teamId, title, description, user.uid, assignedTo, createdAt, createdAt, durationMinutes, dueAt, reminderAt, priority, key, requestHash),
    db.prepare(
      `INSERT INTO task_activity (id, task_id, team_id, actor_id, action, details_json, created_at)
       SELECT ?, id, team_id, ?, 'created', ?, created_at FROM tasks WHERE id = ?`,
    ).bind(randomId(), user.uid, JSON.stringify({ assignedTo, durationMinutes }), taskId),
    db.prepare(
      `UPDATE team_metrics SET tasks_total = tasks_total + 1, active_tasks = active_tasks + 1, revision = revision + 1, updated_at = ?
       WHERE team_id = ? AND EXISTS (SELECT 1 FROM tasks WHERE id = ?)`,
    ).bind(createdAt, teamId, taskId),
    db.prepare(
      `INSERT INTO member_metrics (team_id, user_id, assigned_count, updated_at)
       SELECT team_id, assigned_to, 1, ? FROM tasks WHERE id = ? AND assigned_to IS NOT NULL
       ON CONFLICT(team_id, user_id) DO UPDATE SET assigned_count = assigned_count + 1, updated_at = excluded.updated_at`,
    ).bind(createdAt, taskId),
    db.prepare(
      `INSERT INTO notifications (id, user_id, team_id, task_id, type, event_key, title, body, created_at)
       SELECT ?, assigned_to, team_id, id, 'assignment', 'assignment:' || id,
              'تنبيه Taskaty', 'تم إسناد مهمة جديدة إليك.', ? FROM tasks
       WHERE id = ? AND assigned_to IS NOT NULL AND assigned_to <> created_by
       ON CONFLICT(user_id, event_key) DO NOTHING`,
    ).bind(randomId(), createdAt, taskId),
    db.prepare(
      `INSERT INTO notification_outbox (id, notification_id, recipient_user_id, task_id, status, available_at, created_at)
       SELECT ?, id, user_id, task_id, 'pending', ?, ? FROM notifications
       WHERE event_key = 'assignment:' || ? AND user_id = (SELECT assigned_to FROM tasks WHERE id = ?)
       ON CONFLICT(notification_id, recipient_user_id) DO NOTHING`,
    ).bind(randomId(), createdAt, createdAt, taskId, taskId),
  ];
  await db.batch(statements);
  const created = await db.prepare("SELECT id FROM tasks WHERE id = ?").bind(taskId).first<{ id: string }>();
  if (!created) {
    const collision = await db
      .prepare("SELECT id, request_hash FROM tasks WHERE created_by = ? AND idempotency_key = ?")
      .bind(user.uid, key)
      .first<{ id: string; request_hash: string | null }>();
    if (!collision || collision.request_hash !== requestHash) throw new ApiError("IDEMPOTENCY_KEY_REUSED", 409);
    return getTask(db, collision.id, user.uid);
  }
  return getTask(db, taskId, user.uid);
}

export async function updateTask(
  db: D1Database,
  taskId: string,
  userId: string,
  input: Record<string, unknown>,
  now = Date.now(),
) {
  const existing = parseTask(
    await db
      .prepare(
        `SELECT id, team_id, title, description, created_by, assigned_to, created_at, updated_at,
                duration_minutes, due_at, reminder_at, reminder_sent_at, priority, status,
                completed_at, is_overdue, overdue_alert_at, version
         FROM tasks WHERE id = ?`,
      )
      .bind(taskId)
      .first<TaskRow>(),
  );
  const membership = await getMembership(db, existing.team_id, userId);
  const expectedVersion = requireInteger(input.expectedVersion, "expectedVersion", 1, Number.MAX_SAFE_INTEGER);
  if (expectedVersion !== existing.version) throw new ApiError("VERSION_CONFLICT", 409, "Task changed. Refresh and retry.");

  const hasContentEdit = ["title", "description", "assignedTo", "durationMinutes", "priority"].some((key) => key in input);
  const canEditContent = membership.role !== "member" || existing.created_by === userId;
  if (hasContentEdit && !canEditContent) throw new ApiError("FORBIDDEN", 403, "Only the creator or a team admin can edit task details.");
  if (input.status !== undefined && existing.created_by !== userId && existing.assigned_to !== userId && membership.role === "member") {
    throw new ApiError("FORBIDDEN", 403, "Only the creator, assignee, or a team admin can change task status.");
  }
  if (hasContentEdit && ["completed", "cancelled"].includes(existing.status)) {
    throw new ApiError("TASK_CLOSED", 409, "Closed tasks cannot be edited.");
  }

  const title = input.title === undefined ? existing.title : requireString(input.title, "title", 1, 240);
  const description = input.description === undefined ? existing.description : optionalString(input.description, "description", 4000) ?? "";
  const durationMinutes = input.durationMinutes === undefined ? existing.duration_minutes : requireInteger(input.durationMinutes, "durationMinutes", 1, 525600);
  const priority = input.priority === undefined ? existing.priority : input.priority;
  if (!(["low", "normal", "high", "urgent"] as unknown[]).includes(priority)) throw new ApiError("INVALID_INPUT", 400, "priority is invalid.");
  const assignedTo = input.assignedTo === undefined ? existing.assigned_to : optionalString(input.assignedTo, "assignedTo", 128);
  if (assignedTo) await getMembership(db, existing.team_id, assignedTo);
  const status = input.status === undefined ? existing.status : input.status;
  if (!(["pending", "in_progress", "completed", "cancelled"] as unknown[]).includes(status)) throw new ApiError("INVALID_INPUT", 400, "status is invalid.");
  if (!ACTIVE_STATUSES.includes(existing.status as (typeof ACTIVE_STATUSES)[number]) && status !== existing.status) {
    throw new ApiError("TASK_CLOSED", 409, "Completed or cancelled tasks cannot be reopened.");
  }
  if (![...ACTIVE_STATUSES, "completed", "cancelled"].includes(status as never)) throw new ApiError("INVALID_INPUT", 400);
  if (existing.is_overdue && durationMinutes !== existing.duration_minutes) {
    throw new ApiError("OVERDUE_DURATION_LOCKED", 409, "Use the overdue task's activity history; its original alert remains final.");
  }

  const updatedAt = nowIso(now);
  const mutationId = randomId();
  const activityEventKey = `mutation:${mutationId}`;
  const dueAt = durationMinutes === existing.duration_minutes ? existing.due_at : nowIso(now + durationMinutes * 60_000);
  const reminderAt = durationMinutes === existing.duration_minutes ? existing.reminder_at : durationMinutes > 30 ? nowIso(now + durationMinutes * 60_000 - 30 * 60_000) : null;
  const completedAt = status === "completed" ? updatedAt : existing.completed_at;
  const newVersion = existing.version + 1;
  const taskUpdate = db.prepare(
    `UPDATE tasks SET title = ?, description = ?, duration_minutes = ?, due_at = ?, reminder_at = ?,
       reminder_sent_at = CASE WHEN duration_minutes <> ? THEN NULL ELSE reminder_sent_at END,
       priority = ?, assigned_to = ?, status = ?, completed_at = ?, updated_at = ?, version = ?, last_mutation_id = ?
     WHERE id = ? AND team_id = ? AND version = ? AND status IN ('pending', 'in_progress')
     RETURNING id, team_id, title, description, created_by, assigned_to, created_at, updated_at,
       duration_minutes, due_at, reminder_at, reminder_sent_at, priority, status, completed_at,
       is_overdue, overdue_alert_at, version`,
  ).bind(title, description, durationMinutes, dueAt, reminderAt, durationMinutes, priority, assignedTo, status, completedAt, updatedAt, newVersion, mutationId, taskId, existing.team_id, expectedVersion);

  const activityAction = status !== existing.status
    ? status === "completed" ? "completed" : status === "cancelled" ? "cancelled" : "started"
    : assignedTo !== existing.assigned_to ? "assigned" : "updated";
  const details = JSON.stringify({ version: newVersion, status, assignedTo, priority });
  const statements = [
    taskUpdate,
    db.prepare(
      `UPDATE team_metrics SET revision = revision + 1, updated_at = ? WHERE team_id = ? AND EXISTS (
         SELECT 1 FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ?
       )`,
    ).bind(updatedAt, existing.team_id, taskId, newVersion, mutationId),
    db.prepare(
      `INSERT INTO task_activity (id, task_id, team_id, actor_id, action, event_key, details_json, created_at)
       SELECT ?, id, team_id, ?, ?, ?, ?, updated_at FROM tasks
       WHERE id = ? AND version = ? AND last_mutation_id = ?
       ON CONFLICT(task_id, event_key) WHERE event_key IS NOT NULL DO NOTHING`,
    ).bind(randomId(), userId, activityAction, activityEventKey, details, taskId, newVersion, mutationId),
  ];
  const reassigned = assignedTo !== existing.assigned_to;
  if (reassigned && existing.assigned_to) {
    statements.push(
      db.prepare(
        `UPDATE member_metrics SET assigned_count = MAX(0, assigned_count - 1), updated_at = ?
         WHERE team_id = ? AND user_id = ? AND EXISTS (
           SELECT 1 FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ?
         )`,
      ).bind(updatedAt, existing.team_id, existing.assigned_to, taskId, newVersion, mutationId),
    );
  }
  if (reassigned && assignedTo) {
    statements.push(
      db.prepare(
        `INSERT INTO member_metrics (team_id, user_id, assigned_count, updated_at)
         SELECT team_id, assigned_to, 1, ? FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ? AND assigned_to IS NOT NULL
         ON CONFLICT(team_id, user_id) DO UPDATE SET assigned_count = assigned_count + 1, updated_at = excluded.updated_at`,
      ).bind(updatedAt, taskId, newVersion, mutationId),
    );
    statements.push(
      db.prepare(
        `INSERT INTO notifications (id, user_id, team_id, task_id, type, event_key, title, body, created_at)
         SELECT ?, assigned_to, team_id, id, 'assignment', ?, 'تنبيه Taskaty', 'تم إسناد مهمة جديدة إليك.', updated_at
         FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ? AND assigned_to IS NOT NULL AND assigned_to <> created_by
         ON CONFLICT(user_id, event_key) DO NOTHING`,
      ).bind(randomId(), `assignment:${taskId}:${newVersion}`, taskId, newVersion, mutationId),
    );
    statements.push(
      db.prepare(
        `INSERT INTO notification_outbox (id, notification_id, recipient_user_id, task_id, status, available_at, created_at)
         SELECT ?, id, user_id, task_id, 'pending', ?, ? FROM notifications WHERE event_key = ?
         ON CONFLICT(notification_id, recipient_user_id) DO NOTHING`,
      ).bind(randomId(), updatedAt, updatedAt, `assignment:${taskId}:${newVersion}`),
    );
  }
  if (existing.status !== status && status === "completed") {
    const onTime = Date.parse(updatedAt) <= Date.parse(dueAt) ? 1 : 0;
    const completionSeconds = Math.max(0, Math.floor((now - Date.parse(existing.created_at)) / 1000));
    statements.push(
      db.prepare(
        `UPDATE team_metrics SET active_tasks = MAX(0, active_tasks - 1), completed_tasks = completed_tasks + 1,
           on_time_completions = on_time_completions + ?, completion_seconds_total = completion_seconds_total + ?, revision = revision + 1, updated_at = ?
         WHERE team_id = ? AND EXISTS (SELECT 1 FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ?)`,
      ).bind(onTime, completionSeconds, updatedAt, existing.team_id, taskId, newVersion, mutationId),
    );
    statements.push(
      db.prepare(
        `UPDATE member_metrics SET completed_count = completed_count + 1,
           on_time_completions = on_time_completions + ?, completion_seconds_total = completion_seconds_total + ?, updated_at = ?
         WHERE team_id = ? AND user_id = ? AND EXISTS (SELECT 1 FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ?)`,
      ).bind(onTime, completionSeconds, updatedAt, existing.team_id, assignedTo ?? existing.assigned_to, taskId, newVersion, mutationId),
    );
    const eventKey = `completion:${taskId}:${newVersion}`;
    statements.push(
      db.prepare(
        `INSERT INTO notification_fanout (id, event_key, team_id, task_id, kind, title, body, created_at)
         SELECT ?, ?, team_id, id, 'completion', 'تنبيه Taskaty', 'تم إنجاز مهمة في فريقك.', updated_at
         FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ? ON CONFLICT(event_key) DO NOTHING`,
      ).bind(randomId(), eventKey, taskId, newVersion, mutationId),
    );
  } else if (existing.status !== status && status === "cancelled") {
    statements.push(
      db.prepare(
        `UPDATE team_metrics SET active_tasks = MAX(0, active_tasks - 1), revision = revision + 1, updated_at = ?
         WHERE team_id = ? AND EXISTS (SELECT 1 FROM tasks WHERE id = ? AND version = ? AND last_mutation_id = ?)`,
      ).bind(updatedAt, existing.team_id, taskId, newVersion, mutationId),
    );
  }
  const results = await db.batch(statements);
  if (!results[0]?.results?.length) {
    const current = await db.prepare("SELECT version FROM tasks WHERE id = ? AND team_id = ?").bind(taskId, existing.team_id).first<{ version: number }>();
    if (!current) throw new ApiError("TASK_NOT_FOUND", 404);
    throw new ApiError("VERSION_CONFLICT", 409, "Task changed. Refresh and retry.");
  }
  return publicTask(results[0].results[0] as unknown as TaskRow);
}

export async function getDashboard(db: D1Database, teamId: string, userId: string, now = Date.now()) {
  await getMembership(db, teamId, userId);
  const metrics = await db
    .prepare(
      `SELECT tasks_total AS totalTasks, active_tasks AS activeTasks, completed_tasks AS completedTasks,
              overdue_tasks AS overdueTasks, on_time_completions AS onTimeCompletions,
              completion_seconds_total AS completionSecondsTotal, updated_at AS updatedAt
       FROM team_metrics WHERE team_id = ?`,
    )
    .bind(teamId)
    .first<Record<string, number | string>>();
  const memberResults = await db
    .prepare(
      `SELECT mm.user_id AS userId, u.display_name AS displayName, mm.assigned_count AS assignedCount,
              mm.completed_count AS completedCount, mm.overdue_count AS overdueCount,
              mm.on_time_completions AS onTimeCompletions,
              mm.completion_seconds_total AS completionSecondsTotal
       FROM member_metrics mm JOIN users u ON u.uid = mm.user_id
       WHERE mm.team_id = ? ORDER BY mm.assigned_count DESC, u.display_name COLLATE NOCASE LIMIT 30`,
    )
    .bind(teamId)
    .all();
  const approaching = await db
    .prepare(
      `SELECT id, team_id, title, description, created_by, assigned_to, created_at, updated_at,
              duration_minutes, due_at, reminder_at, reminder_sent_at, priority, status,
              completed_at, is_overdue, overdue_alert_at, version FROM tasks
       WHERE team_id = ? AND status IN ('pending', 'in_progress') AND is_overdue = 0
         AND due_at > ? AND due_at <= ? ORDER BY due_at LIMIT 10`,
    )
    .bind(teamId, nowIso(now), nowIso(now + 2 * 60 * 60_000))
    .all<TaskRow>();
  const memberRows = (memberResults.results ?? []) as Array<Record<string, unknown>>;
  const members = memberRows.map((member) => {
    const assigned = Number(member.assignedCount ?? 0);
    const completed = Number(member.completedCount ?? 0);
    const onTime = Number(member.onTimeCompletions ?? 0);
    const seconds = Number(member.completionSecondsTotal ?? 0);
    return {
      ...member,
      onTimeCompletionPercent: completed ? Math.round((onTime / completed) * 100) : null,
      averageCompletionSeconds: completed ? Math.round(seconds / completed) : null,
      completionPercent: assigned ? Math.round((completed / assigned) * 100) : 0,
    };
  });
  const summary = metrics ?? {
    totalTasks: 0,
    activeTasks: 0,
    completedTasks: 0,
    overdueTasks: 0,
    onTimeCompletions: 0,
    completionSecondsTotal: 0,
    updatedAt: nowIso(now),
  };
  const completedTasks = Number(summary.completedTasks ?? 0);
  const onTime = Number(summary.onTimeCompletions ?? 0);
  const seconds = Number(summary.completionSecondsTotal ?? 0);
  return {
    serverTime: nowIso(now),
    summary: {
      ...summary,
      onTimeCompletionPercent: completedTasks ? Math.round((onTime / completedTasks) * 100) : null,
      averageCompletionSeconds: completedTasks ? Math.round(seconds / completedTasks) : null,
    },
    members,
    approaching: (approaching.results ?? []).map(publicTask),
  };
}
