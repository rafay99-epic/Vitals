import type { ReadableStore } from "@vitals/client-runtime";
import { useCallback, useRef, useSyncExternalStore } from "react";

export const useStore = <T>(store: ReadableStore<T>): T => useSyncExternalStore(store.subscribe, store.get, store.get);

export const useSelect = <T, S>(store: ReadableStore<T>, select: (value: T) => S): S => {
  const cache = useRef<{ readonly source: T; readonly select: (value: T) => S; readonly value: S } | null>(null);
  const read = useCallback(() => {
    const source = store.get();
    const cached = cache.current;
    if (cached !== null && cached.select === select && Object.is(cached.source, source)) return cached.value;
    const value = select(source);
    cache.current = { source, select, value };
    return value;
  }, [store, select]);
  return useSyncExternalStore(store.subscribe, read, read);
};
