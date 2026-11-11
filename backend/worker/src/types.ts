export interface D1Meta {
  changes?: number;
  last_row_id?: number;
  rows_read?: number;
  rows_written?: number;
}

export interface D1Result<T = Record<string, unknown>> {
  results?: T[];
  success: boolean;
  meta?: D1Meta;
  error?: string;
}

export interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  first<T = Record<string, unknown>>(columnName?: string): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<D1Result<T>>;
  run<T = Record<string, unknown>>(): Promise<D1Result<T>>;
}

export interface D1Database {
  prepare(query: string): D1PreparedStatement;
  batch<T = unknown>(statements: D1PreparedStatement[]): Promise<D1Result<T>[]>;
}

export interface Env {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
  FCM_TOKEN_ENCRYPTION_KEY?: string;
  APP_ORIGIN?: string;
}

export interface AuthUser {
  uid: string;
  email: string;
  displayName: string;
  photoUrl: string | null;
  emailVerified: boolean;
}

export interface FirebaseClaims {
  sub: string;
  user_id?: string;
  email?: string;
  email_verified?: boolean;
  name?: string;
  picture?: string;
  aud: string | string[];
  iss: string;
  exp: number;
  iat: number;
  auth_time: number;
  firebase?: { sign_in_provider?: string };
}

export interface TaskRow {
  id: string;
  team_id: string;
  title: string;
  description: string;
  created_by: string;
  assigned_to: string | null;
  created_at: string;
  updated_at: string;
  duration_minutes: number;
  due_at: string;
  reminder_at: string | null;
  reminder_sent_at: string | null;
  priority: "low" | "normal" | "high" | "urgent";
  status: "pending" | "in_progress" | "completed" | "cancelled";
  completed_at: string | null;
  is_overdue: number;
  overdue_alert_at: string | null;
  version: number;
}

export interface ScheduledController {
  cron: string;
  scheduledTime: number;
}

export interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}
