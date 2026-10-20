import type { Database } from "bun:sqlite";
import { type Alert, type SequencedEvent, type SystemEvent, SystemEvent as SystemEventSchema } from "@vitals/contracts";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Bridge } from "../bridge/Bridge.ts";

const REPLAY_LIMIT = 128;

const encodeEvent = Schema.encodeSync(Schema.fromJsonString(SystemEventSchema));
const decodeEvent = Schema.decodeUnknownSync(Schema.fromJsonString(SystemEventSchema));

const eventKind = (event: SystemEvent): string => {
  switch (event._tag) {
    case "WillSleep":
      return "mac.willSleep";
    case "DidWake":
      return "mac.didWake";
    case "WillPowerOff":
      return "mac.willPowerOff";
    case "ThermalChanged":
      return "mac.thermal";
    case "KeepAwakeChanged":
      return "mac.keepAwake";
    case "AlertRaised":
      return "alert.raised";
    case "AlertCleared":
      return "alert.cleared";
    case "CommandUpdated":
      return `command.${event.receipt.status}`;
  }
};

export class EventLog extends Context.Service<
  EventLog,
  {
    readonly append: (event: SystemEvent) => Effect.Effect<SequencedEvent>;
    readonly subscribe: (afterSeq: number | null) => Stream.Stream<SequencedEvent>;
    readonly lastSeq: Effect.Effect<number>;
    readonly published: Stream.Stream<SequencedEvent>;
  }
>()("@vitals/gateway/EventLog") {}

export const layer = (db: Database) =>
  Layer.effect(
    EventLog,
    Effect.gen(function* () {
      const activity = yield* ActivityLog;
      const bridge = yield* Bridge;
      const hub = yield* PubSub.unbounded<SequencedEvent>();
      const insert = db.prepare("INSERT INTO system_events (at, event_json) VALUES (?, ?)");
      const after = db.prepare("SELECT seq, event_json FROM system_events WHERE seq > ? ORDER BY seq LIMIT ?");
      const latest = db.prepare("SELECT coalesce(max(seq), 0) AS seq FROM system_events");

      const append = (event: SystemEvent) =>
        Effect.gen(function* () {
          const seq = Number(insert.run(event.at, encodeEvent(event)).lastInsertRowid);
          const sequenced = { seq, event };
          const commandId = event._tag === "CommandUpdated" ? event.receipt.id : null;
          const level = event._tag === "CommandUpdated" && event.receipt.status === "failed" ? "warn" : "info";
          activity.record({
            at: event.at,
            source: "desktop",
            level,
            kind: eventKind(event),
            commandId,
            deviceId: event._tag === "CommandUpdated" ? event.receipt.deviceId : null,
            data: { seq },
          });
          yield* PubSub.publish(hub, sequenced);
          return sequenced;
        });

      const alertRows = db.prepare(
        "SELECT event_json FROM system_events WHERE json_extract(event_json, '$._tag') IN ('AlertRaised', 'AlertCleared') ORDER BY seq DESC LIMIT 500",
      );
      const open = new Map<string, Alert>();
      for (const row of (alertRows.all() as ReadonlyArray<{ event_json: string }>).toReversed()) {
        const event = decodeEvent(row.event_json);
        if (event._tag === "AlertRaised") open.set(event.alert.id, event.alert);
        if (event._tag === "AlertCleared") open.delete(event.alert.id);
      }
      const now = Date.now();
      for (const alert of open.values()) {
        yield* append({ _tag: "AlertCleared", at: now, alert: { ...alert, clearedAt: now } });
      }

      yield* bridge.messages.pipe(
        Stream.runForEach((message) => (message.t === "event" ? Effect.asVoid(append(message.event)) : Effect.void)),
        Effect.forkScoped,
      );

      const subscribe = (afterSeq: number | null) =>
        Stream.unwrap(
          Effect.gen(function* () {
            const subscription = yield* PubSub.subscribe(hub);
            const replay =
              afterSeq === null
                ? []
                : (after.all(afterSeq, REPLAY_LIMIT) as ReadonlyArray<{ seq: number; event_json: string }>).map((row) => ({
                    seq: row.seq,
                    event: decodeEvent(row.event_json),
                  }));
            const floor = replay.at(-1)?.seq ?? afterSeq ?? -1;
            return Stream.concat(
              Stream.fromIterable(replay),
              Stream.fromSubscription(subscription).pipe(Stream.filter((item) => item.seq > floor)),
            );
          }),
        );

      return EventLog.of({
        append,
        subscribe,
        lastSeq: Effect.sync(() => (latest.get() as { seq: number }).seq),
        published: Stream.fromPubSub(hub),
      });
    }),
  );
