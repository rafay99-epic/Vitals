import type { ReadableStore } from "@vitals/client-runtime";
import { useSyncExternalStore } from "react";

export const useStore = <T>(store: ReadableStore<T>): T => useSyncExternalStore(store.subscribe, store.get, store.get);

export const useSelect = <T, S>(store: ReadableStore<T>, select: (value: T) => S): S =>
  useSyncExternalStore(
    store.subscribe,
    () => select(store.get()),
    () => select(store.get()),
  );
