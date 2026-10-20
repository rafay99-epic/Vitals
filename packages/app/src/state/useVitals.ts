import type { LiveSample } from "@vitals/contracts";
import { useCallback, useEffect, useState } from "react";

import { useRemote } from "../connection/useRemote.ts";
import { hasSignal, type Link, linkOf, sampleWord, stateWord, type Word } from "./vitals.ts";
import { useSelect, useStore } from "./useStore.ts";

export const useLatest = <S>(select: (sample: LiveSample | null) => S): S => useSelect(useRemote().live.latest, select);

export const useLink = (): Link => linkOf(useStore(useRemote().connection.state));

export const useSignal = (): boolean => hasSignal(useStore(useRemote().connection.state));

export const useWord = (): Word => {
  const remote = useRemote();
  const vitals = useSelect(remote.live.latest, sampleWord);
  const alerts = useStore(remote.events.alerts);
  const signal = useSignal();
  const asleep = useStore(remote.events.asleepSince) !== null;
  const calmed = useStore(remote.events.calmed);
  return stateWord({ vitals, alerts, signal, asleep, calmed });
};

export const useNow = (everyMs: number): number => {
  const [now, setNow] = useState(Date.now);
  const tick = useCallback(() => setNow(Date.now()), []);
  useEffect(() => {
    const timer = setInterval(tick, everyMs);
    return () => clearInterval(timer);
  }, [everyMs, tick]);
  return now;
};
