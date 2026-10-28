import * as SQLite from "expo-sqlite";

import type { JournalEntry, JournalStore } from "../state/journal.ts";

const KEPT = 500;

export const openJournal = (): JournalStore => {
  const db = SQLite.openDatabaseSync("vitals-client.db");
  db.execSync("CREATE TABLE IF NOT EXISTS journal (seq INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL);");
  return {
    read: () => db.getAllSync<JournalEntry>("SELECT at, kind, text FROM journal ORDER BY seq DESC LIMIT ?", [KEPT]).toReversed(),
    write: (entry) => {
      db.runSync("INSERT INTO journal (at, kind, text) VALUES (?, ?, ?)", [entry.at, entry.kind, entry.text]);
      db.runSync("DELETE FROM journal WHERE seq <= (SELECT seq FROM journal ORDER BY seq DESC LIMIT 1 OFFSET ?)", [KEPT]);
    },
    clear: () => db.runSync("DELETE FROM journal"),
  };
};
