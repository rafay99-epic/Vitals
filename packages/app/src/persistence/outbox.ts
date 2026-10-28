import type { ClientEvent } from "@vitals/contracts";
import * as SQLite from "expo-sqlite";

import { type Outbox, decodeEvent } from "./outboxShared.ts";

const CAP = 5_000;

export const openOutbox = (): Outbox => {
  const db = SQLite.openDatabaseSync("vitals-client.db");
  db.execSync(
    "PRAGMA journal_mode = WAL; CREATE TABLE IF NOT EXISTS outbox (event_id TEXT PRIMARY KEY, body TEXT NOT NULL, at INTEGER NOT NULL);",
  );
  return {
    push: (event: ClientEvent) => {
      db.runSync("INSERT OR IGNORE INTO outbox (event_id, body, at) VALUES (?, ?, ?)", [event.eventId, JSON.stringify(event), event.at]);
      db.runSync("DELETE FROM outbox WHERE event_id IN (SELECT event_id FROM outbox ORDER BY at DESC LIMIT -1 OFFSET ?)", [CAP]);
    },
    take: (limit: number) =>
      db
        .getAllSync<{ body: string }>("SELECT body FROM outbox ORDER BY at LIMIT ?", [limit])
        .map((row) => decodeEvent(row.body))
        .filter((event): event is ClientEvent => event !== null),
    remove: (ids: ReadonlyArray<string>) => {
      for (const id of ids) db.runSync("DELETE FROM outbox WHERE event_id = ?", [id]);
    },
    clear: () => {
      db.runSync("DELETE FROM outbox");
    },
  };
};
