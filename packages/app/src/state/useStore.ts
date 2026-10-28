import type { ReadableStore } from "@vitals/client-runtime";
import { useCallback, useRef, useSyncExternalStore } from "react";

export const useStore = <T>(store: ReadableStore<T>): T => useSyncExternalStore(store.subscribe, store.get, store.get);

const shallowEqual = (a: unknown, b: unknown): boolean => {
  if (Object.is(a, b)) return true;
  if (typeof a !== "object" || typeof b !== "object" || a === null || b === null || Array.isArray(a) || Array.isArray(b)) return false;
  const left = Object.entries(a);
  const right = new Map(Object.entries(b));
  return left.length === right.size && left.every(([key, value]) => right.has(key) && Object.is(value, right.get(key)));
};

export const useSelect = <T, S>(store: ReadableStore<T>, select: (value: T) => S): S => {
  const cache = useRef<{ readonly source: T; readonly select: (value: T) => S; readonly value: S } | null>(null);
  const read = useCallback(() => {
    const source = store.get();
    const cached = cache.current;
    if (cached !== null && cached.select === select && Object.is(cached.source, source)) return cached.value;
    const fresh = select(source);
    const value = cached !== null && cached.select === select && shallowEqual(cached.value, fresh) ? cached.value : fresh;
    cache.current = { source, select, value };
    return value;
  }, [store, select]);
  return useSyncExternalStore(store.subscribe, read, read);
};
