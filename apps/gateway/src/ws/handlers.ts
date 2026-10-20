import { type Query, type QueryResult, PROTOCOL_VERSION, Unavailable, VitalsRpc } from "@vitals/contracts";
import * as Effect from "effect/Effect";

import { ActivityLog } from "../activity/ActivityLog.ts";
import type { Session } from "../auth/Auth.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { CommandService } from "../commands/CommandService.ts";
import { EventLog } from "../events/EventLog.ts";
import { Hubs } from "../live/Hubs.ts";

const unexpected = (tag: string) => new Unavailable({ message: `Unexpected ${tag} reply from Vitals` });

const MAX_CLIENT_DATA_BYTES = 2_048;

const boundedData = (data: Readonly<Record<string, unknown>>): Readonly<Record<string, unknown>> => {
  const bytes = JSON.stringify(data).length;
  return bytes <= MAX_CLIENT_DATA_BYTES ? data : { truncated: true, bytes };
};

export const handlersLayer = (session: Session, connectionId: string) =>
  VitalsRpc.toLayer(
    Effect.gen(function* () {
      const bridge = yield* Bridge;
      const hubs = yield* Hubs;
      const events = yield* EventLog;
      const commands = yield* CommandService;
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
            const open = yield* events.openAlerts(0);
            return {
              protocol: PROTOCOL_VERSION,
              mac: identity?.mac ?? null,
              keepAwake: identity?.keepAwake ?? null,
              lastEventSeq: open.lastSeq,
              alerts: open.alerts,
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
                data: boundedData(event.data),
              });
            }
            return { accepted: batch.length };
          }),
      });
    }),
  );
