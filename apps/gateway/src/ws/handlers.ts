import { type Query, type QueryResult, PROTOCOL_VERSION, Unavailable, VitalsRpc } from "@vitals/contracts";
import * as Effect from "effect/Effect";

import { ActivityLog } from "../activity/ActivityLog.ts";
import type { Session } from "../auth/Auth.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { CommandService } from "../commands/CommandService.ts";
import { EventLog } from "../events/EventLog.ts";
import { Hubs } from "../live/Hubs.ts";
import { Store } from "../persistence/Store.ts";

const unexpected = (tag: string) => new Unavailable({ message: `Unexpected ${tag} reply from Vitals` });

export const handlersLayer = (session: Session, connectionId: string) =>
  VitalsRpc.toLayer(
    Effect.gen(function* () {
      const bridge = yield* Bridge;
      const hubs = yield* Hubs;
      const events = yield* EventLog;
      const commands = yield* CommandService;
      const store = yield* Store;
      const activity = yield* ActivityLog;
      const caller = { id: session.device.id, name: session.device.name };

      const ask = <Tag extends QueryResult["_tag"]>(q: Extract<Query, { readonly _tag: Tag }>) =>
        bridge.query(q).pipe(
          Effect.filterOrFail(
            (result): result is Extract<QueryResult, { readonly _tag: Tag }> => result._tag === q._tag,
            (result) => unexpected(result._tag),
          ),
        );

      return VitalsRpc.of({
        "server.hello": () =>
          Effect.gen(function* () {
            const identity = yield* bridge.identity.pipe(Effect.orElseSucceed(() => null));
            return {
              protocol: PROTOCOL_VERSION,
              mac: identity?.mac ?? null,
              keepAwake: identity?.keepAwake ?? null,
              lastEventSeq: yield* events.lastSeq,
              serverTime: Date.now(),
              scopes: session.device.scopes,
            };
          }),
        "stats.live": ({ topics }) => hubs.live(topics),
        "history.range": (input) =>
          ask({ _tag: "History", input }).pipe(Effect.map((result) => result.result)),
        "system.events": ({ afterSeq }) => events.subscribe(afterSeq),
        "processes.watch": (input) => hubs.processes(input),
        "apps.list": () => ask({ _tag: "Apps" }).pipe(Effect.map((result) => result.result)),
        "command.run": (input) => commands.run(caller, input),
        "command.cancel": ({ commandId }) => commands.cancel(caller, commandId),
        "command.log": () => commands.log,
        "guard.watch": () => hubs.guard,
        "guard.update": (settings) =>
          ask({ _tag: "SetGuard", settings }).pipe(Effect.map((result) => result.settings)),
        "clipboard.get": () =>
          ask({ _tag: "Clipboard" }).pipe(Effect.map((result) => ({ text: result.text }))),
        "activity.ingest": ({ events: batch }) =>
          Effect.sync(() => {
            for (const event of batch) {
              activity.record({
                eventId: event.eventId,
                at: event.at,
                source: "client",
                level: event.level,
                kind: event.kind,
                deviceId: session.device.id,
                connectionId,
                data: event.data,
              });
            }
            return { accepted: batch.length };
          }),
        "push.register": ({ token }) =>
          Effect.sync(() => {
            store.registerPush(session.device.id, token, Date.now());
            activity.record({
              at: Date.now(),
              source: "gateway",
              level: "info",
              kind: "push.registered",
              deviceId: session.device.id,
              data: {},
            });
            return {};
          }),
      });
    }),
  );
