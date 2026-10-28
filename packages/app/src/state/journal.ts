import { Store } from "@vitals/client-runtime";

import { openJournal } from "../persistence/journal";

/** What a journal line is about. */
export type JournalKind = "app" | "net" | "nearby" | "pair" | "link" | "tunnel" | "check";

export interface JournalEntry {
  readonly at: number;
  readonly kind: JournalKind;
  readonly text: string;
}

export interface JournalStore {
  readonly read: () => ReadonlyArray<JournalEntry>;
  readonly write: (entry: JournalEntry) => void;
  readonly clear: () => void;
}

const KEPT = 500;

const disk = ((): JournalStore | null => {
  try {
    return openJournal();
  } catch {
    return null;
  }
})();

const safely = <A>(read: () => A, fallback: A): A => {
  try {
    return read();
  } catch {
    return fallback;
  }
};

/**
 * The phone's own record of how it tried to reach the Mac: launches, networks, Macs seen nearby,
 * pairing and connection attempts with their low-level reasons. Kept on disk across launches and
 * reinstall-free updates, so a link that broke while nobody watched can still be read afterwards.
 */
export const journal = new Store<ReadonlyArray<JournalEntry>>(safely(() => disk?.read() ?? [], []));

/** The latest line of each kind, so a state reported again (a poll, a heartbeat) is kept once. */
const latest = new Map<JournalKind, string>();

/** Adds a line, unless it repeats the latest line of its kind. */
export const note = (kind: JournalKind, text: string): void => {
  if (latest.get(kind) === text) return;
  latest.set(kind, text);
  const entry = { at: Date.now(), kind, text };
  journal.set([...journal.get().slice(-(KEPT - 1)), entry]);
  safely(() => disk?.write(entry), undefined);
};

export const clearJournal = (): void => {
  latest.clear();
  journal.set([]);
  safely(() => disk?.clear(), undefined);
};
