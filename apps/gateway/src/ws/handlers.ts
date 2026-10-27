import { CommandRejected, PROTOCOL_VERSION, VitalsRpc } from "@vitals/contracts";
import * as Effect from "effect/Effect";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Auth, type Session } from "../auth/Auth.ts";
import { Bridge, ask } from "../bridge/Bridge.ts";
import { ClipStore } from "../clips/ClipStore.ts";
import { CommandService } from "../commands/CommandService.ts";
import { DropStore } from "../drop/DropStore.ts";
import { EventLog } from "../events/EventLog.ts";
import { FsService } from "../fs/FsService.ts";
import { TerminalService } from "../terminal/TerminalService.ts";
import { Lan } from "../lan/Lan.ts";
import { Hubs } from "../live/Hubs.ts";
import { Store } from "../persistence/Store.ts";
import { Serve } from "../tailscale/Serve.ts";

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
      const lan = yield* Lan;
      const store = yield* Store;
      const auth = yield* Auth;
      const serve = yield* Serve;
      const clips = yield* ClipStore;
      const drops = yield* DropStore;
      const files = yield* FsService;
      const terminals = yield* TerminalService;
      const caller = { id: session.device.id, name: session.device.name };
      const clipCaller = { deviceId: session.device.id, name: session.device.name, connectionId };
      const dropCaller = { ...clipCaller, platform: session.device.platform };

      return VitalsRpc.of({
        "server.hello": () =>
          Effect.gen(function* () {
            const identity = yield* bridge.identity.pipe(Effect.orElseSucceed(() => null));
            const open = yield* events.openAlerts(0);
            const routes = lan.routes((yield* serve.status).url);
            return {
              ...(routes === null ? {} : { routes }),
              protocol: PROTOCOL_VERSION,
              mac: identity?.mac ?? null,
              keepAwake: identity?.keepAwake ?? null,
              lastEventSeq: open.lastSeq,
              alerts: open.alerts,
              serverTime: Date.now(),
              scopes: session.device.scopes,
              clips: true,
              drop: true,
              fs: true,
              terminal: true,
              audio: true,
            };
          }),
        "stats.live": ({ topics }) => hubs.live(topics),
        "history.range": (input) =>
          ask(bridge, { _tag: "History", input }).pipe(Effect.map((result) => result.result)),
        "system.events": ({ afterSeq }) => events.subscribe(afterSeq),
        "processes.watch": (input) => hubs.processes(input),
        "apps.list": () => ask(bridge, { _tag: "Apps" }).pipe(Effect.map((result) => result.result)),
        "command.run": (input) => commands.run(caller, input),
        "command.cancel": ({ commandId }) => commands.cancel(caller, commandId),
        "command.log": () => commands.log,
        "guard.watch": () => hubs.guard,
        "system.audio": () => hubs.audio,
        "guard.update": (settings) =>
          ask(bridge, { _tag: "SetGuard", settings }).pipe(Effect.map((result) => result.settings)),
        "clipboard.get": () =>
          ask(bridge, { _tag: "Clipboard" }).pipe(Effect.map((result) => ({ text: result.text }))),
        "clips.watch": () => clips.watch,
        "clips.read": (input) => clips.read(clipCaller, input),
        "clips.pin": (input) => clips.pin(clipCaller, input),
        "clips.remove": (input) => clips.remove(clipCaller, input).pipe(Effect.as({})),
        "clips.send.begin": (input) => clips.begin(clipCaller, input),
        "clips.send.chunk": (input) => clips.chunk(clipCaller, input),
        "clips.send.finish": (input) => clips.finish(clipCaller, input),
        "clips.put": (input) => clips.put(clipCaller, input),
        "drop.watch": () => drops.watch(dropCaller),
        "drop.offer": (input) => {
          const relay = input.relay === undefined ? null : store.device(input.relay);
          if (input.relay !== undefined && (relay === null || relay.revokedAt !== null || relay.platform === "web" || relay.id === session.device.id || !relay.scopes.includes("files"))) {
            return Effect.fail(new CommandRejected({ message: "That device can't receive files" }));
          }
          return input.dest === undefined ? drops.offer(dropCaller, input) : files.destination(input.dest).pipe(Effect.flatMap((dest) => drops.offer(dropCaller, { ...input, dest })));
        },
        "drop.accept": (input) => drops.accept(dropCaller, input),
        "drop.decline": (input) => drops.decline(dropCaller, input),
        "drop.cancel": (input) => drops.cancel(dropCaller, input),
        "drop.ticket": (input) => drops.ticket(dropCaller, input),
        "drop.received": (input) => drops.received(dropCaller, input),
        "fs.roots": (input) => files.roots(input),
        "fs.devices": () => files.devices(session.device.id),
        "fs.serve": (input) => files.serve(dropCaller, input),
        "fs.reply": (input) => files.reply(dropCaller, input).pipe(Effect.as({})),
        "fs.pull": (input) => files.pull(session.device.id, input),
        "fs.list": (input) => files.list(input),
        "fs.search": (input) => files.search(input),
        "fs.thumbs": (input) => files.thumbs(input),
        "fs.get": (input) => (session.device.scopes.includes("files") ? files.get(dropCaller, input) : Effect.fail(new CommandRejected({ message: "This device can't receive files. Allow it on your Mac." }))),
        "fs.open": (input) => files.open(input).pipe(Effect.as({})),
        "fs.trash": (input) => files.trash(dropCaller, input),
        "terminal.list": () => terminals.list,
        "terminal.open": (input) => terminals.open(clipCaller, input),
        "terminal.attach": (input) => terminals.attach(clipCaller, input),
        "terminal.write": (input) => terminals.write(input).pipe(Effect.as({})),
        "terminal.resize": (input) => terminals.resize(input).pipe(Effect.as({})),
        "terminal.close": (input) => terminals.close(clipCaller, input).pipe(Effect.as({})),
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
        "device.forget": () =>
          Effect.gen(function* () {
            activity.record({ at: Date.now(), source: "client", level: "info", kind: "device.unpaired", deviceId: session.device.id, data: {} });
            yield* Effect.forkDetach(Effect.andThen(Effect.sleep("200 millis"), auth.revoke(session.device.id)));
            return {};
          }),
        "device.lanKey": ({ key }) =>
          Effect.sync(() => {
            if (store.bindLanKey(session.device.id, key, Date.now())) {
              activity.record({ at: Date.now(), source: "gateway", level: "info", kind: "device.lan.bound", deviceId: session.device.id, data: {} });
            }
            return {};
          }),
      });
    }),
  );
