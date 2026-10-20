import {
  type AdminResult,
  type FromApp,
  type MacInfo,
  type KeepAwakeState,
  type Query,
  type QueryResult,
  type ToApp,
  FromApp as FromAppSchema,
  MAX_BRIDGE_LINE_BYTES,
  ToApp as ToAppSchema,
  Unavailable,
} from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Context from "effect/Context";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Ref from "effect/Ref";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";

export interface BridgeTransport {
  readonly lines: Stream.Stream<string>;
  readonly write: (line: string) => void;
  readonly onClose: () => void;
}

export class BridgeTransportService extends Context.Service<BridgeTransportService, BridgeTransport>()(
  "@vitals/gateway/BridgeTransport",
) {}

export interface AppIdentity {
  readonly mac: MacInfo;
  readonly keepAwake: KeepAwakeState;
}

export type AdminHandler = (op: Extract<FromApp, { t: "admin" }>["op"]) => Effect.Effect<AdminResult, string>;

export class Bridge extends Context.Service<
  Bridge,
  {
    readonly send: (message: ToApp) => Effect.Effect<void>;
    readonly messages: Stream.Stream<FromApp>;
    readonly identity: Effect.Effect<AppIdentity, Unavailable>;
    readonly query: (q: Query) => Effect.Effect<QueryResult, Unavailable>;
    readonly serveAdmin: (handler: AdminHandler) => Effect.Effect<never>;
  }
>()("@vitals/gateway/Bridge") {}

const decodeLine = Schema.decodeUnknownResult(Schema.fromJsonString(FromAppSchema));
const encodeLine = Schema.encodeSync(Schema.fromJsonString(ToAppSchema));
const decodeResultId = Schema.decodeUnknownResult(
  Schema.fromJsonString(Schema.Struct({ t: Schema.Literal("result"), id: Schema.String })),
);

const QUERY_TIMEOUT = "10 seconds";

export const layer = Layer.effect(
  Bridge,
  Effect.gen(function* () {
    const transport = yield* BridgeTransportService;
    const activity = yield* ActivityLog;
    const hub = yield* PubSub.unbounded<FromApp>();
    const identity = yield* Ref.make<AppIdentity | null>(null);
    const pending = new Map<string, Deferred.Deferred<QueryResult, Unavailable>>();

    const log = (level: "info" | "warn" | "error", kind: string, data: Record<string, unknown>) =>
      activity.record({ at: Date.now(), source: "gateway", level, kind, data });

    const send = (message: ToApp) => Effect.sync(() => transport.write(encodeLine(message)));

    const handle = (message: FromApp) =>
      Effect.gen(function* () {
        switch (message.t) {
          case "hello":
            yield* Ref.set(identity, { mac: message.mac, keepAwake: message.keepAwake });
            log("info", "bridge.up", { vitals: message.mac.vitalsVersion, channel: message.mac.channel });
            break;
          case "result": {
            const waiter = pending.get(message.id);
            if (waiter === undefined) break;
            pending.delete(message.id);
            if (message.ok === null) {
              yield* Deferred.fail(waiter, new Unavailable({ message: message.error ?? "query failed" }));
            } else {
              yield* Deferred.succeed(waiter, message.ok);
            }
            break;
          }
          case "log":
            activity.record({ at: Date.now(), source: "desktop", level: message.level, kind: message.kind, data: message.data });
            break;
          case "event":
            if (message.event._tag === "KeepAwakeChanged") {
              const state = message.event.state;
              yield* Ref.update(identity, (current) => (current === null ? null : { ...current, keepAwake: state }));
            }
            break;
          default:
            break;
        }
        yield* PubSub.publish(hub, message);
      });

    yield* transport.lines.pipe(
      Stream.runForEach((line) => {
        if (line.length === 0) return Effect.void;
        if (line.length > MAX_BRIDGE_LINE_BYTES) {
          log("warn", "bridge.oversized", { bytes: line.length });
          return Effect.void;
        }
        const decoded = decodeLine(line);
        if (decoded._tag === "Failure") {
          log("warn", "bridge.invalid", { preview: line.slice(0, 120), issue: String(decoded.failure).slice(0, 300) });
          const reply = decodeResultId(line);
          const id = reply._tag === "Success" ? reply.success.id : "";
          const waiter = pending.get(id);
          if (waiter === undefined) return Effect.void;
          pending.delete(id);
          return Deferred.fail(waiter, new Unavailable({ message: "Vitals sent an invalid reply" }));
        }
        return handle(decoded.success);
      }),
      Effect.ensuring(
        Effect.sync(() => {
          log("warn", "bridge.down", {});
          transport.onClose();
        }),
      ),
      Effect.forkScoped,
    );

    const query = (q: Query) =>
      Effect.gen(function* () {
        const waiter = yield* Deferred.make<QueryResult, Unavailable>();
        const id = newId();
        pending.set(id, waiter);
        yield* send({ t: "query", id, q });
        return yield* Deferred.await(waiter).pipe(
          Effect.timeoutOrElse({
            duration: QUERY_TIMEOUT,
            orElse: () => Effect.fail(new Unavailable({ message: "Vitals did not answer in time" })),
          }),
          Effect.ensuring(Effect.sync(() => pending.delete(id))),
        );
      });

    const serveAdmin = (handler: AdminHandler) =>
      Stream.fromPubSub(hub).pipe(
        Stream.filter((message): message is Extract<FromApp, { t: "admin" }> => message.t === "admin"),
        Stream.runForEach((message) =>
          handler(message.op).pipe(
            Effect.match({
              onFailure: (error) => ({ t: "adminResult" as const, id: message.id, ok: null, error }),
              onSuccess: (ok) => ({ t: "adminResult" as const, id: message.id, ok, error: null }),
            }),
            Effect.flatMap(send),
          ),
        ),
        Effect.andThen(Effect.never),
      );

    return Bridge.of({
      send,
      messages: Stream.fromPubSub(hub),
      identity: Ref.get(identity).pipe(
        Effect.flatMap((value) =>
          value === null ? Effect.fail(new Unavailable({ message: "Vitals is not connected" })) : Effect.succeed(value),
        ),
      ),
      query,
      serveAdmin,
    });
  }),
);

export const stdioTransport = Layer.sync(BridgeTransportService, () => ({
  lines: Stream.fromReadableStream({
    evaluate: () => Bun.stdin.stream(),
    onError: (error) => error,
  }).pipe(Stream.decodeText(), Stream.splitLines, Stream.orDie),
  write: (line: string) => {
    process.stdout.write(`${line}\n`);
  },
  onClose: () => {
    process.kill(process.pid, "SIGTERM");
  },
}));
