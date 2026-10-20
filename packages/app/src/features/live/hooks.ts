import { useFocusEffect } from "@react-navigation/native";
import { type LiveSample, Topic } from "@vitals/contracts";
import * as Schema from "effect/Schema";
import { useCallback } from "react";

import { useRemote } from "../../connection/useRemote.ts";
import { useSelect } from "../../state/useStore.ts";

const isTopic = Schema.is(Topic);

export const useLiveTopics = (topics: ReadonlyArray<Topic>): void => {
  const remote = useRemote();
  const key = topics.join(",");
  useFocusEffect(useCallback(() => remote.live.acquire(key.split(",").filter(isTopic)), [remote, key]));
};

export const useLatest = <S>(select: (sample: LiveSample | null) => S): S => {
  const remote = useRemote();
  return useSelect(remote.live.latest, select);
};
