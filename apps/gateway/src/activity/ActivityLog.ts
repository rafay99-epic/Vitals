import type { Database, Statement } from "bun:sqlite";
import type { ActivityLevel, ActivitySource } from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Schedule from "effect/Schedule";

export interface ActivityEvent {
  readonly eventId?: string;
  readonly at: number;
  readonly source: ActivitySource;
  readonly level: ActivityLevel;
  readonly kind: string;
  readonly deviceId?: string | null;
  readonly connectionId?: string | null;
  readonly rpc?: string | null;
  readonly commandId?: string | null;
  readonly durationMs?: number | null;
  readonly data?: Readonly<Record<string, unknown>>;
}

export interface FrameRecord {
  readonly connectionId: string;
  readonly at: number;
  readonly dir: "in" | "out";
  readonly rpcId: string | null;
  readonly method: string | null;
  readonly tag: string;
  readonly bytes: number;
}

export interface ConnectionOpen {
  readonly id: string;
  readonly deviceId: string;
  readonly openedAt: number;
  readonly tsLogin: string | null;
  readonly clientVersion: string | null;
}

const MAX_QUEUE = 20_000;
const RETENTION = { frames: 72 * 3_600_000, events: 30 * 86_400_000, connections: 90 * 86_400_000 } as const;
const MAX_BYTES = 512 * 1024 * 1024;
const PRUNE_PAGE = 2_000;

const isDroppable = (event: ActivityEvent): boolean =>
  event.level === "debug" && !/^(auth|command|alert|pairing|session)\./.test(event.kind);

class ActivityWriter {
  private events: Array<ActivityEvent> = [];
  private frames: Array<FrameRecord> = [];
  private connectionDeltas = new Map<string, { msgsIn: number; msgsOut: number; bytesIn: number; bytesOut: number }>();
  private dropped = 0;

  private readonly db: Database;
  private readonly insertEvent: Statement;
  private readonly insertFrame: Statement;
  private readonly openConnection: Statement;
  private readonly closeConnection: Statement;
  private readonly bumpConnection: Statement;
  private readonly bumpRollup: Statement;

  constructor(db: Database) {
    this.db = db;
    this.insertEvent = db.prepare(
      `INSERT OR IGNORE INTO events (event_id, at, received_at, source, level, kind, device_id, connection_id, rpc, command_id, duration_ms, data_json)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    this.insertFrame = db.prepare(
      "INSERT INTO frames (connection_id, at, dir, rpc_id, method, tag, bytes) VALUES (?, ?, ?, ?, ?, ?, ?)",
    );
    this.openConnection = db.prepare(
      "INSERT OR REPLACE INTO connections (id, device_id, opened_at, ts_login, client_version) VALUES (?, ?, ?, ?, ?)",
    );
    this.closeConnection = db.prepare("UPDATE connections SET closed_at = ?, close_reason = ? WHERE id = ?");
    this.bumpConnection = db.prepare(
      "UPDATE connections SET msgs_in = msgs_in + ?, msgs_out = msgs_out + ?, bytes_in = bytes_in + ?, bytes_out = bytes_out + ? WHERE id = ?",
    );
    this.bumpRollup = db.prepare(
      `INSERT INTO rollups_minute (minute, kind, count, errors) VALUES (?, ?, 1, ?)
       ON CONFLICT (minute, kind) DO UPDATE SET count = count + 1, errors = errors + excluded.errors`,
    );
  }

  get pending(): number {
    return this.events.length + this.frames.length;
  }

  record(event: ActivityEvent): void {
    if (this.pending >= MAX_QUEUE) {
      if (this.frames.length > 0) {
        this.frames.shift();
        this.dropped += 1;
      } else if (isDroppable(event)) {
        this.dropped += 1;
        return;
      }
    }
    this.events.push(event);
  }

  frame(frame: FrameRecord): void {
    const delta = this.connectionDeltas.get(frame.connectionId) ?? { msgsIn: 0, msgsOut: 0, bytesIn: 0, bytesOut: 0 };
    if (frame.dir === "in") {
      delta.msgsIn += 1;
      delta.bytesIn += frame.bytes;
    } else {
      delta.msgsOut += 1;
      delta.bytesOut += frame.bytes;
    }
    this.connectionDeltas.set(frame.connectionId, delta);
    if (this.pending >= MAX_QUEUE) {
      this.dropped += 1;
      return;
    }
    this.frames.push(frame);
  }

  connectionOpened(open: ConnectionOpen): void {
    this.flush();
    this.openConnection.run(open.id, open.deviceId, open.openedAt, open.tsLogin, open.clientVersion);
  }

  connectionClosed(id: string, at: number, reason: string): void {
    this.flush();
    this.closeConnection.run(at, reason, id);
  }

  flush(now = Date.now()): number {
    if (this.dropped > 0) {
      this.events.push({ at: now, source: "gateway", level: "warn", kind: "log.dropped", data: { count: this.dropped } });
      this.dropped = 0;
    }
    if (this.events.length === 0 && this.frames.length === 0 && this.connectionDeltas.size === 0) return 0;
    const events = this.events.splice(0, this.events.length);
    const frames = this.frames.splice(0, this.frames.length);
    const deltas = [...this.connectionDeltas];
    this.connectionDeltas.clear();
    this.db.transaction(() => {
      for (const event of events) {
        this.insertEvent.run(
          event.eventId ?? newId(),
          event.at,
          now,
          event.source,
          event.level,
          event.kind,
          event.deviceId ?? null,
          event.connectionId ?? null,
          event.rpc ?? null,
          event.commandId ?? null,
          event.durationMs ?? null,
          JSON.stringify(event.data ?? {}),
        );
        this.bumpRollup.run(Math.floor(event.at / 60_000) * 60_000, event.kind, event.level === "error" ? 1 : 0);
      }
      for (const frame of frames) {
        this.insertFrame.run(frame.connectionId, frame.at, frame.dir, frame.rpcId, frame.method, frame.tag, frame.bytes);
      }
      for (const [id, delta] of deltas) {
        this.bumpConnection.run(delta.msgsIn, delta.msgsOut, delta.bytesIn, delta.bytesOut, id);
      }
    })();
    return events.length + frames.length;
  }

  prune(now = Date.now()): void {
    const page = (sql: string, cutoff: number) => {
      let removed = PRUNE_PAGE;
      while (removed === PRUNE_PAGE) {
        removed = this.db.run(sql, [cutoff, PRUNE_PAGE]).changes;
      }
    };
    page("DELETE FROM frames WHERE seq IN (SELECT seq FROM frames WHERE at < ? LIMIT ?)", now - RETENTION.frames);
    page("DELETE FROM events WHERE seq IN (SELECT seq FROM events WHERE at < ? LIMIT ?)", now - RETENTION.events);
    page(
      "DELETE FROM connections WHERE id IN (SELECT id FROM connections WHERE opened_at < ? LIMIT ?)",
      now - RETENTION.connections,
    );
    page("DELETE FROM system_events WHERE seq IN (SELECT seq FROM system_events WHERE at < ? LIMIT ?)", now - RETENTION.events);
    page(
      "DELETE FROM rollups_minute WHERE rowid IN (SELECT rowid FROM rollups_minute WHERE minute < ? LIMIT ?)",
      now - RETENTION.events,
    );
    const oldestFirst = [
      "DELETE FROM frames WHERE seq IN (SELECT seq FROM frames ORDER BY seq LIMIT ?)",
      "DELETE FROM events WHERE seq IN (SELECT seq FROM events ORDER BY seq LIMIT ?)",
      "DELETE FROM rollups_minute WHERE rowid IN (SELECT rowid FROM rollups_minute ORDER BY minute LIMIT ?)",
    ];
    for (const sql of oldestFirst) {
      while (this.sizeBytes() > MAX_BYTES && this.db.run(sql, [PRUNE_PAGE]).changes > 0) {
        this.db.run("PRAGMA incremental_vacuum(256)");
      }
    }
    this.db.run("PRAGMA incremental_vacuum(256)");
  }

  private sizeBytes(): number {
    const count = (this.db.query("PRAGMA page_count").get() as { page_count: number }).page_count;
    const size = (this.db.query("PRAGMA page_size").get() as { page_size: number }).page_size;
    return count * size;
  }
}

export class ActivityLog extends Context.Service<
  ActivityLog,
  {
    readonly record: (event: ActivityEvent) => void;
    readonly frame: (frame: FrameRecord) => void;
    readonly connectionOpened: (open: ConnectionOpen) => void;
    readonly connectionClosed: (id: string, at: number, reason: string) => void;
    readonly flush: Effect.Effect<void>;
  }
>()("@vitals/gateway/ActivityLog") {}

export const layer = (db: Database) =>
  Layer.effect(
    ActivityLog,
    Effect.gen(function* () {
      const writer = new ActivityWriter(db);
      const flush = Effect.sync(() => writer.flush());
      yield* flush.pipe(Effect.repeat(Schedule.spaced("250 millis")), Effect.forkScoped);
      yield* Effect.sync(() => writer.prune()).pipe(Effect.repeat(Schedule.spaced("1 hour")), Effect.forkScoped);
      yield* Effect.addFinalizer(() => flush);
      return ActivityLog.of({
        record: (event) => writer.record(event),
        frame: (frame) => writer.frame(frame),
        connectionOpened: (open) => writer.connectionOpened(open),
        connectionClosed: (id, at, reason) => writer.connectionClosed(id, at, reason),
        flush: Effect.asVoid(flush),
      });
    }),
  );
