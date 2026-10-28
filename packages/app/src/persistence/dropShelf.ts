import * as SQLite from "expo-sqlite";

import type { Shelf } from "../state/drops.ts";

export const openShelf = (): Shelf => {
  const db = SQLite.openDatabaseSync("vitals-client.db");
  db.execSync("CREATE TABLE IF NOT EXISTS drop_shelf (key TEXT PRIMARY KEY, body TEXT NOT NULL);");
  return {
    read: async (key) => (await db.getFirstAsync<{ body: string }>("SELECT body FROM drop_shelf WHERE key = ?", [key]))?.body ?? null,
    write: (key, body) => void db.runAsync("INSERT OR REPLACE INTO drop_shelf (key, body) VALUES (?, ?)", [key, body]).catch(() => undefined),
  };
};
