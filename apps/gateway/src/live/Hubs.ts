import type { AudioState, GuardState, LiveSample, ProcessesSnapshot, ProcessesWatchInput, Topic } from "@vitals/contracts";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Stream from "effect/Stream";

import { Bridge } from "../bridge/Bridge.ts";

const LIVE_INTERVAL_MS = 1000;
const IDLE_INTERVAL_MS = 2000;

export class Hubs extends Context.Service<
  Hubs,
  {
    readonly live: (topics: ReadonlyArray<Topic>) => Stream.Stream<LiveSample>;
    readonly processes: (input: ProcessesWatchInput) => Stream.Stream<ProcessesSnapshot>;
    readonly guard: Stream.Stream<GuardState>;
    readonly audio: Stream.Stream<AudioState>;
  }
>()("@vitals/gateway/Hubs") {}

const project = (sample: LiveSample, topics: ReadonlySet<Topic>): LiveSample => ({
  seq: sample.seq,
  at: sample.at,
  ...(topics.has("cpu") && sample.cpu !== undefined ? { cpu: sample.cpu } : {}),
  ...(topics.has("gpu") && sample.gpu !== undefined ? { gpu: sample.gpu } : {}),
  ...(topics.has("thermal") && sample.thermal !== undefined ? { thermal: sample.thermal } : {}),
  ...(topics.has("fans") && sample.fans !== undefined ? { fans: sample.fans } : {}),
  ...(topics.has("memory") && sample.memory !== undefined ? { memory: sample.memory } : {}),
  ...(topics.has("battery") && sample.battery !== undefined ? { battery: sample.battery } : {}),
  ...(topics.has("power") && sample.power !== undefined ? { power: sample.power } : {}),
  ...(topics.has("power") && sample.systemWatts !== undefined ? { systemWatts: sample.systemWatts } : {}),
  ...(topics.has("network") && sample.network !== undefined ? { network: sample.network } : {}),
  ...(topics.has("disk") && sample.disk !== undefined ? { disk: sample.disk } : {}),
});

export const layer = Layer.effect(
  Hubs,
  Effect.gen(function* () {
    const bridge = yield* Bridge;
    const samples = yield* PubSub.sliding<LiveSample>({ capacity: 1, replay: 1 });
    const processSnapshots = yield* PubSub.sliding<ProcessesSnapshot>({ capacity: 1, replay: 1 });
    const guardStates = yield* PubSub.sliding<GuardState>({ capacity: 1, replay: 1 });
    const audioStates = yield* PubSub.sliding<AudioState>({ capacity: 1, replay: 1 });

    const topicCounts = new Map<Topic, number>();
    const processWatchers = new Map<symbol, ProcessesWatchInput>();
    let guardWatchers = 0;
    let lastNeed = "";

    const pushNeed = Effect.suspend(() => {
      const topics = [...topicCounts.entries()].filter(([, count]) => count > 0).map(([topic]) => topic);
      const limit = Math.max(0, ...[...processWatchers.values()].map((input) => input.limit));
      const message = {
        t: "need" as const,
        topics,
        intervalMs: topics.length > 0 ? LIVE_INTERVAL_MS : IDLE_INTERVAL_MS,
        processes: limit > 0 ? { sortBy: "cpu" as const, limit } : null,
        guard: guardWatchers > 0,
      };
      const key = JSON.stringify(message);
      if (key === lastNeed) return Effect.void;
      lastNeed = key;
      return bridge.send(message);
    });

    yield* bridge.messages.pipe(
      Stream.runForEach((message) => {
        switch (message.t) {
          case "sample":
            return PubSub.publish(samples, message.data);
          case "processes":
            return PubSub.publish(processSnapshots, message.data);
          case "guard":
            return PubSub.publish(guardStates, message.data);
          case "audio":
            return PubSub.publish(audioStates, message.data);
          case "hello":
            lastNeed = "";
            return pushNeed;
          default:
            return Effect.void;
        }
      }),
      Effect.forkScoped,
    );

    const live = (topics: ReadonlyArray<Topic>) => {
      const wanted = new Set(topics);
      return Stream.unwrap(
        Effect.gen(function* () {
          yield* Effect.acquireRelease(
            Effect.suspend(() => {
              for (const topic of wanted) topicCounts.set(topic, (topicCounts.get(topic) ?? 0) + 1);
              return pushNeed;
            }),
            () =>
              Effect.suspend(() => {
                for (const topic of wanted) topicCounts.set(topic, Math.max(0, (topicCounts.get(topic) ?? 1) - 1));
                return pushNeed;
              }),
          );
          return Stream.fromPubSub(samples).pipe(Stream.map((sample) => project(sample, wanted)));
        }),
      );
    };

    const processes = (input: ProcessesWatchInput) =>
      Stream.unwrap(
        Effect.gen(function* () {
          const key = Symbol("watcher");
          yield* Effect.acquireRelease(
            Effect.suspend(() => {
              processWatchers.set(key, input);
              return pushNeed;
            }),
            () =>
              Effect.suspend(() => {
                processWatchers.delete(key);
                return pushNeed;
              }),
          );
          return Stream.fromPubSub(processSnapshots).pipe(
            Stream.map((snapshot) => {
              const rows = [...snapshot.rows]
                .sort((left, right) =>
                  input.sortBy === "cpu" ? right.cpuPercent - left.cpuPercent : right.memoryBytes - left.memoryBytes,
                )
                .slice(0, input.limit);
              return { ...snapshot, rows };
            }),
          );
        }),
      );

    const guard = Stream.unwrap(
      Effect.gen(function* () {
        yield* Effect.acquireRelease(
          Effect.suspend(() => {
            guardWatchers += 1;
            return pushNeed;
          }),
          () =>
            Effect.suspend(() => {
              guardWatchers = Math.max(0, guardWatchers - 1);
              return pushNeed;
            }),
        );
        return Stream.fromPubSub(guardStates);
      }),
    );

    return Hubs.of({
      live,
      processes,
      guard,
      audio: Stream.fromPubSub(audioStates),
    });
  }),
);
