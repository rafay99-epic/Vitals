import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Queue from "effect/Queue";
import type * as Scope from "effect/Scope";

export interface LiveConnection {
  readonly id: string;
  readonly deviceId: string;
}

export interface Presence {
  readonly deviceId: string;
  readonly online: boolean;
}

export class Connections extends Context.Service<
  Connections,
  {
    readonly add: (connection: LiveConnection) => Effect.Effect<void>;
    readonly remove: (id: string) => Effect.Effect<void>;
    readonly count: Effect.Effect<number>;
    readonly connectedDevices: Effect.Effect<ReadonlySet<string>>;
    readonly changes: Effect.Effect<void>;
    readonly presence: Effect.Effect<PubSub.Subscription<Presence>, never, Scope.Scope>;
  }
>()("@vitals/gateway/Connections") {}

export const layer = Layer.effect(
  Connections,
  Effect.gen(function* () {
    const live = new Map<string, LiveConnection>();
    const changed = yield* Queue.sliding<void>(1);
    const presence = yield* PubSub.unbounded<Presence>();
    const notify = Queue.offer(changed, undefined);
    const online = (deviceId: string) => [...live.values()].some((connection) => connection.deviceId === deviceId);
    return Connections.of({
      add: (connection) => Effect.suspend(() => {
        const first = !online(connection.deviceId);
        live.set(connection.id, connection);
        if (first) PubSub.publishUnsafe(presence, { deviceId: connection.deviceId, online: true });
        return Effect.asVoid(notify);
      }),
      remove: (id) => Effect.suspend(() => {
        const connection = live.get(id);
        live.delete(id);
        if (connection !== undefined && !online(connection.deviceId)) PubSub.publishUnsafe(presence, { deviceId: connection.deviceId, online: false });
        return Effect.asVoid(notify);
      }),
      count: Effect.sync(() => live.size),
      connectedDevices: Effect.sync(() => new Set([...live.values()].map((connection) => connection.deviceId))),
      changes: Queue.take(changed),
      presence: PubSub.subscribe(presence),
    });
  }),
);
