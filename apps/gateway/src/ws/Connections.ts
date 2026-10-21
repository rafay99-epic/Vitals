import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";

export interface LiveConnection {
  readonly id: string;
  readonly deviceId: string;
}

export class Connections extends Context.Service<
  Connections,
  {
    readonly add: (connection: LiveConnection) => Effect.Effect<void>;
    readonly remove: (id: string) => Effect.Effect<void>;
    readonly count: Effect.Effect<number>;
    readonly connectedDevices: Effect.Effect<ReadonlySet<string>>;
    readonly changes: Effect.Effect<void>;
  }
>()("@vitals/gateway/Connections") {}

export const layer = Layer.effect(
  Connections,
  Effect.gen(function* () {
    const live = new Map<string, LiveConnection>();
    const changed = yield* Queue.sliding<void>(1);
    const notify = Queue.offer(changed, undefined);
    return Connections.of({
      add: (connection) => Effect.suspend(() => {
        live.set(connection.id, connection);
        return Effect.asVoid(notify);
      }),
      remove: (id) => Effect.suspend(() => {
        live.delete(id);
        return Effect.asVoid(notify);
      }),
      count: Effect.sync(() => live.size),
      connectedDevices: Effect.sync(() => new Set([...live.values()].map((connection) => connection.deviceId))),
      changes: Queue.take(changed),
    });
  }),
);
