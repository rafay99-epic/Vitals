import type { JournalStore } from "../state/journal.ts";

/** The web client keeps its journal in memory only. */
export const openJournal = (): JournalStore => ({ read: () => [], write: () => undefined, clear: () => undefined });
