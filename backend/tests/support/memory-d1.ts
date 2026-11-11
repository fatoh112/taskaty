import initSqlJs from "sql.js";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import type { D1Database, D1PreparedStatement, D1Result } from "../../worker/src/types.ts";

type SqlJsDatabase = InstanceType<Awaited<ReturnType<typeof initSqlJs>>["Database"]>;
type SqlJsStatement = ReturnType<SqlJsDatabase["prepare"]>;

class Statement implements D1PreparedStatement {
  private values: unknown[] = [];

  constructor(private readonly db: SqlJsDatabase, private readonly sql: string) {}

  bind(...values: unknown[]): D1PreparedStatement {
    this.values = values;
    return this;
  }

  private execute(): { rows: Record<string, unknown>[]; changes: number } {
    const statement: SqlJsStatement = this.db.prepare(this.sql);
    try {
      const bindings = this.values.map((value) => value === true ? 1 : value === false ? 0 : value) as (string | number | null | Uint8Array)[];
      statement.bind(bindings);
      const rows: Record<string, unknown>[] = [];
      while (statement.step()) rows.push(statement.getAsObject() as Record<string, unknown>);
      return { rows, changes: this.db.getRowsModified() };
    } finally {
      statement.free();
    }
  }

  async first<T = Record<string, unknown>>(columnName?: string): Promise<T | null> {
    const result = this.execute().rows[0];
    if (!result) return null;
    if (columnName) return (result[columnName] as T | undefined) ?? null;
    return result as T;
  }

  async all<T = Record<string, unknown>>(): Promise<D1Result<T>> {
    const result = this.execute();
    return { results: result.rows as T[], success: true, meta: { changes: result.changes } };
  }

  async run<T = Record<string, unknown>>(): Promise<D1Result<T>> {
    const result = this.execute();
    return { results: result.rows as T[], success: true, meta: { changes: result.changes } };
  }
}

class MemoryD1 implements D1Database {
  constructor(private readonly db: SqlJsDatabase) {}
  prepare(query: string): D1PreparedStatement { return new Statement(this.db, query); }

  async batch<T = unknown>(statements: D1PreparedStatement[]): Promise<D1Result<T>[]> {
    this.db.run("BEGIN IMMEDIATE");
    try {
      const results: D1Result<T>[] = [];
      for (const statement of statements) results.push(await statement.all<T>());
      this.db.run("COMMIT");
      return results;
    } catch (error) {
      this.db.run("ROLLBACK");
      throw error;
    }
  }

  async exec(sql: string): Promise<void> { this.db.run(sql); }
  close(): void { this.db.close(); }
}

export async function createMemoryD1(): Promise<MemoryD1> {
  const sqlUrl = import.meta.resolve("sql.js");
  const wasmPath = fileURLToPath(new URL("./sql-wasm.wasm", sqlUrl));
  const SQL = await initSqlJs({ locateFile: () => wasmPath });
  const db = new SQL.Database();
  const migrationPath = fileURLToPath(new URL("../../migrations/0001_initial.sql", import.meta.url));
  const migration = await readFile(migrationPath, "utf8");
  db.run(migration);
  return new MemoryD1(db);
}
