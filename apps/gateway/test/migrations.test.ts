import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { REMOTE_MIGRATIONS } from "../src/persistence/migrations.ts";
import { openDatabase } from "../src/persistence/sqlite.ts";

describe("remote migrations", () => {
  test("devices that could operate the Mac gain files, and phones with files gain fsRead, once", () => {
    const dir = mkdtempSync(join(tmpdir(), "vitals-migrate-"));
    const path = join(dir, "remote.db");
    const before = openDatabase(path, REMOTE_MIGRATIONS.filter((migration) => migration.id < 4));
    const insert = before.prepare("INSERT INTO devices (id, name, platform, model, app_version, scopes, created_at) VALUES (?, 'P', 'android', 'P', '1', ?, 0)");
    insert.run("operator", JSON.stringify(["read", "operate"]));
    insert.run("reader", JSON.stringify(["read"]));
    insert.run("already", JSON.stringify(["read", "operate", "files"]));
    before.prepare("INSERT INTO devices (id, name, platform, model, app_version, scopes, created_at) VALUES ('browser', 'B', 'web', 'B', '1', ?, 0)").run(JSON.stringify(["read", "operate"]));
    before.close();

    const after = openDatabase(path, REMOTE_MIGRATIONS);
    const scopes = Object.fromEntries(
      after.query<{ id: string; scopes: string }, []>("SELECT id, scopes FROM devices").all().map((row) => [row.id, JSON.parse(row.scopes)]),
    );
    after.close();
    rmSync(dir, { recursive: true, force: true });

    expect(scopes).toEqual({
      operator: ["read", "operate", "files", "fsRead"],
      reader: ["read"],
      already: ["read", "operate", "files", "fsRead"],
      browser: ["read", "operate", "files"],
    });
  });
});
