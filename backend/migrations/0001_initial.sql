PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  uid TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  display_name TEXT NOT NULL,
  photo_url TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS teams (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
  owner_id TEXT NOT NULL REFERENCES users(uid),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS team_members (
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK(role IN ('owner', 'admin', 'member')),
  joined_at TEXT NOT NULL,
  left_at TEXT,
  PRIMARY KEY (team_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_team_members_user ON team_members(user_id, joined_at DESC);
CREATE INDEX IF NOT EXISTS idx_team_members_active ON team_members(team_id, user_id) WHERE left_at IS NULL;

CREATE TABLE IF NOT EXISTS team_invitations (
  id TEXT PRIMARY KEY,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('admin', 'member')),
  created_by TEXT NOT NULL REFERENCES users(uid),
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  max_uses INTEGER NOT NULL CHECK(max_uses BETWEEN 1 AND 50),
  used_count INTEGER NOT NULL DEFAULT 0 CHECK(used_count >= 0),
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_invitations_team ON team_invitations(team_id, expires_at);

CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 240),
  description TEXT NOT NULL DEFAULT '' CHECK(length(description) <= 4000),
  created_by TEXT NOT NULL REFERENCES users(uid),
  assigned_to TEXT REFERENCES users(uid),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  duration_minutes INTEGER NOT NULL CHECK(duration_minutes BETWEEN 1 AND 525600),
  due_at TEXT NOT NULL,
  reminder_at TEXT,
  reminder_sent_at TEXT,
  priority TEXT NOT NULL DEFAULT 'normal' CHECK(priority IN ('low', 'normal', 'high', 'urgent')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'in_progress', 'completed', 'cancelled')),
  completed_at TEXT,
  is_overdue INTEGER NOT NULL DEFAULT 0 CHECK(is_overdue IN (0, 1)),
  overdue_alert_at TEXT,
  version INTEGER NOT NULL DEFAULT 1 CHECK(version >= 1),
  last_mutation_id TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT,
  request_hash TEXT,
  UNIQUE(created_by, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_tasks_team_created ON tasks(team_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_team_status_due ON tasks(team_id, status, due_at);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_status ON tasks(team_id, assigned_to, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_team_title ON tasks(team_id, title COLLATE NOCASE, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_overdue_due ON tasks(due_at, id) WHERE is_overdue = 0 AND status IN ('pending', 'in_progress');
CREATE INDEX IF NOT EXISTS idx_tasks_reminder_due ON tasks(reminder_at, id) WHERE reminder_sent_at IS NULL AND status IN ('pending', 'in_progress');

CREATE TABLE IF NOT EXISTS task_activity (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  actor_id TEXT NOT NULL REFERENCES users(uid),
  action TEXT NOT NULL CHECK(action IN ('created', 'updated', 'assigned', 'started', 'completed', 'cancelled', 'overdue', 'reminded')),
  event_key TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_task_activity_task ON task_activity(task_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_task_activity_team ON task_activity(team_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_activity_event ON task_activity(task_id, event_key) WHERE event_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS device_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  token_ciphertext TEXT NOT NULL,
  token_iv TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('android', 'ios', 'web')),
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  invalidated_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id, invalidated_at, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK(type IN ('assignment', 'reminder', 'overdue', 'completion', 'team')),
  event_key TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  read_at TEXT,
  UNIQUE(user_id, event_key)
);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications(user_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON notifications(user_id, created_at DESC) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_fanout ON notifications(team_id, event_key, user_id, created_at);

CREATE TABLE IF NOT EXISTS notification_outbox (
  id TEXT PRIMARY KEY,
  notification_id TEXT NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  recipient_user_id TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'sending', 'sent', 'no_device', 'dead')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts >= 0),
  available_at TEXT NOT NULL,
  lease_until TEXT,
  delivered_at TEXT,
  last_error_code TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(notification_id, recipient_user_id)
);
CREATE INDEX IF NOT EXISTS idx_outbox_ready ON notification_outbox(status, available_at, lease_until, created_at);

CREATE TABLE IF NOT EXISTS notification_fanout (
  id TEXT PRIMARY KEY,
  event_key TEXT NOT NULL UNIQUE,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK(kind IN ('reminder', 'overdue', 'completion')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  cursor_user_id TEXT NOT NULL DEFAULT '',
  lease_until TEXT,
  completed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_notification_fanout_ready ON notification_fanout(completed_at, lease_until, created_at);

CREATE TABLE IF NOT EXISTS deadline_events (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK(kind IN ('reminder', 'overdue')),
  occurred_at TEXT NOT NULL,
  UNIQUE(task_id, kind)
);
CREATE INDEX IF NOT EXISTS idx_deadline_events_team ON deadline_events(team_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS team_metrics (
  team_id TEXT PRIMARY KEY REFERENCES teams(id) ON DELETE CASCADE,
  revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0),
  tasks_total INTEGER NOT NULL DEFAULT 0,
  active_tasks INTEGER NOT NULL DEFAULT 0,
  completed_tasks INTEGER NOT NULL DEFAULT 0,
  overdue_tasks INTEGER NOT NULL DEFAULT 0,
  on_time_completions INTEGER NOT NULL DEFAULT 0,
  completion_seconds_total INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS member_metrics (
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  assigned_count INTEGER NOT NULL DEFAULT 0,
  completed_count INTEGER NOT NULL DEFAULT 0,
  overdue_count INTEGER NOT NULL DEFAULT 0,
  on_time_completions INTEGER NOT NULL DEFAULT 0,
  completion_seconds_total INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(team_id, user_id)
);

CREATE TABLE IF NOT EXISTS api_rate_limits (
  bucket_key TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL,
  PRIMARY KEY(bucket_key, window_start)
);
CREATE INDEX IF NOT EXISTS idx_rate_limit_window ON api_rate_limits(window_start);

CREATE TABLE IF NOT EXISTS worker_heartbeats (
  name TEXT PRIMARY KEY,
  last_started_at TEXT NOT NULL,
  last_finished_at TEXT,
  last_error_code TEXT,
  overdue_processed INTEGER NOT NULL DEFAULT 0,
  reminders_processed INTEGER NOT NULL DEFAULT 0,
  fanout_processed INTEGER NOT NULL DEFAULT 0,
  outbox_processed INTEGER NOT NULL DEFAULT 0
);
