import { useFocusEffect } from "@react-navigation/native";
import { type Topic, Topic as TopicSchema } from "@vitals/contracts";
import * as Schema from "effect/Schema";
import { useCallback } from "react";

import { useRemote } from "../../connection/useRemote.ts";

const isTopic = Schema.is(TopicSchema);

export const useLiveTopics = (topics: ReadonlyArray<Topic>): void => {
  const remote = useRemote();
  const key = topics.join(",");
  useFocusEffect(useCallback(() => remote.live.acquire(key.split(",").filter(isTopic)), [remote, key]));
};
