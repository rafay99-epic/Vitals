import { Database } from "bun:sqlite";

export interface Migration {
  readonly id: number;
  readonly sql: string;
}

const PRAGMAS = [
  "PRAGMA journal_mode = WAL",
  "PRAGMA synchronous = NORMAL",
  "PRAGMA busy_timeout = 5000",
  "PRAGMA foreign_keys = ON",
  "PRAGMA journal_size_limit = 33554432",
  "PRAGMA checkpoint_fullfsync = ON",
];

export const openDatabase = (path: string, migrations: ReadonlyArray<Migration>): Database => {
  const db = new Database(path, { create: true, strict: true });
  const fresh = (db.query("SELECT count(*) AS n FROM sqlite_master").get() as { n: number }).n === 0;
  if (fresh) db.run("PRAGMA auto_vacuum = INCREMENTAL");
  for (const pragma of PRAGMAS) db.run(pragma);
  migrate(db, migrations);
  return db;
};

const migrate = (db: Database, migrations: ReadonlyArray<Migration>): void => {
  db.run("CREATE TABLE IF NOT EXISTS migrations (id INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)");
  const applied = new Set(
    db
      .query("SELECT id FROM migrations")
      .all()
      .map((row) => (row as { id: number }).id),
  );
  const ordered = [...migrations].sort((left, right) => left.id - right.id);
  const highest = Math.max(0, ...applied);
  const skipped = ordered.find((migration) => !applied.has(migration.id) && migration.id < highest);
  if (skipped !== undefined) {
    throw new Error(`migration ${skipped.id} would be skipped; database is ahead of this build`);
  }
  for (const migration of ordered) {
    if (applied.has(migration.id)) continue;
    db.transaction(() => {
      db.run(migration.sql);
      db.run("INSERT INTO migrations (id, applied_at) VALUES (?, ?)", [migration.id, Date.now()]);
    })();
  }
};
