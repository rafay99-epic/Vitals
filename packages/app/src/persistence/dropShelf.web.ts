import type { Shelf } from "../state/drops.ts";

export const openShelf = (): Shelf => {
  const kept = new Map<string, string>();
  return {
    read: async (key) => kept.get(key) ?? null,
    write: (key, body) => void kept.set(key, body),
  };
};
