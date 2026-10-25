import type { Database } from "bun:sqlite";

import {
  type DeviceId,
  type Drop,
  type DropEvent,
  type DropIdInput,
  type DropOfferInput,
  type DropPeer,
  type DropOffered,
  type DropPolicy,
  type DropReceivedInput,
  type DropState,
  type DropTicket,
  type FromApp,
  type MacDropFile,
  type Platform,
  type ToApp,
  CommandRejected,
  DROP_LIMITS,
  DropFileId,
  DropId,
  Unavailable,
} from "@vitals/contracts";
import { formatBytes, newId } from "@vitals/shared";
import * as Cause from "effect/Cause";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Queue from "effect/Queue";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { GatewayConfig } from "../config.ts";
import { hashFile } from "../hash.ts";
import { randomToken } from "../persistence/RemoteStore.ts";
import { Store } from "../persistence/Store.ts";
import { Connections } from "../ws/Connections.ts";
import { type DropFileRecord, type DropRecord, type DropRoute, DropDb, makeDrop } from "./DropDb.ts";
import { dropFiles, parseContentRange, parseRange, partCount } from "./DropFiles.ts";

export interface DropCaller {
  readonly deviceId: DeviceId;
  readonly name: string;
  readonly platform: Platform;
  readonly connectionId: string;
}

type DropError = CommandRejected | Unavailable;

export class DropStore extends Context.Service<
  DropStore,
  {
    readonly watch: (caller: DropCaller) => Stream.Stream<DropEvent>;
    readonly offer: (caller: DropCaller, input: DropOfferInput) => Effect.Effect<DropOffered, DropError>;
    readonly accept: (caller: DropCaller, input: DropIdInput) => Effect.Effect<DropOffered, DropError>;
    readonly pull: (caller: DropCaller, files: ReadonlyArray<MacDropFile>) => Effect.Effect<DropOffered, DropError>;
    readonly decline: (caller: DropCaller, input: DropIdInput) => Effect.Effect<Drop, DropError>;
    readonly cancel: (caller: DropCaller, input: DropIdInput) => Effect.Effect<Drop, DropError>;
    readonly ticket: (caller: DropCaller, input: DropIdInput) => Effect.Effect<DropTicket, DropError>;
    readonly received: (caller: DropCaller, input: DropReceivedInput) => Effect.Effect<Drop, DropError>;
    readonly handle: (request: Request, route: DropRoute) => Promise<Response>;
  }
>()("@vitals/gateway/DropStore") {}

type Ending = "done" | "failed" | "cancelled" | "declined";
type Going = "asking" | "waiting" | "running" | "paused";

const DAY_MS = 86_400_000;
const RETAIN_MS = 7 * DAY_MS;
const MAX_FINISHED = 200;
const MAX_ACTIVE = { device: 8, total: 64 } as const;
const TICKETS_PER_DROP = 8;
const PROGRESS_EVERY = "250 millis";
const SWEEP_EVERY = "10 minutes";
const PART = DROP_LIMITS.partBytes;
const DEFAULT_POLICY: DropPolicy = { autoAccept: true, askWeb: true, maxBytes: 50 * 1024 ** 3 };
const DROP_PATH = /^\/api\/drop\/([A-Za-z0-9-]{8,64})\/([A-Za-z0-9-]{1,64})$/;
const EMPTY_SHA256 = new Bun.CryptoHasher("sha256").digest("hex");
const ENDINGS: ReadonlySet<DropState> = new Set<DropState>(["done", "failed", "cancelled", "declined"]);

const GONE = "That drop is gone";
const ENDED = "That drop already ended";

const makeDropId = Schema.decodeUnknownSync(DropId);
const makeFileId = Schema.decodeUnknownSync(DropFileId);

const rejected = (message: string) => new CommandRejected({ message });
const unavailable = (message: string) => new Unavailable({ message });

const ended = (drop: DropRecord): boolean => ENDINGS.has(drop.state);

const hashTicket = (ticket: string): Uint8Array => new Bun.CryptoHasher("sha256").update(ticket).digest();

const problem = (status: number, code: string, message: string, headers: Record<string, string> = {}) =>
  Response.json({ code, message }, { status, headers: { "cache-control": "no-store", ...headers } });

const wire = (drop: DropRecord): Drop => {
  let bytes = 0;
  let done = 0;
  const files = drop.files.map((file) => {
    bytes += file.size;
    done += file.done;
    return { id: file.id, name: file.name, path: file.path, size: file.size, mime: file.mime, sha256: file.sha256, done: file.done };
  });
  return {
    id: drop.id,
    from: drop.from,
    to: drop.to,
    files,
    bytes,
    done,
    state: drop.state,
    route: drop.route,
    createdAt: drop.createdAt,
    updatedAt: drop.updatedAt,
    error: drop.error,
  };
};

const fileRecord = (
  index: number,
  fields: { readonly name: string; readonly path: string | null; readonly mime: string | null },
  size: number,
  sha256: string | null,
  origin: string | null,
): DropFileRecord => ({
  id: makeFileId(String(index)),
  name: fields.name,
  path: fields.path,
  size,
  mime: fields.mime,
  origin,
  parts: new Set(),
  sha256,
  done: 0,
  complete: false,
  verifying: false,
});

const blocked = (drop: DropRecord): Response | null => {
  switch (drop.state) {
    case "running":
      return null;
    case "paused":
      return problem(423, "paused", "This drop is paused");
    case "asking":
    case "waiting":
      return problem(409, "not_accepted", "This drop has not been accepted yet");
    default:
      return problem(410, "ended", ENDED);
  }
};

export const layer = (database: Database) =>
  Layer.effect(
    DropStore,
    Effect.gen(function* () {
      const config = yield* GatewayConfig;
      const bridge = yield* Bridge;
      const store = yield* Store;
      const connections = yield* Connections;
      const activity = yield* ActivityLog;
      const db = new DropDb(database);
      const files = dropFiles(config.dataDir);
      const hub = yield* PubSub.unbounded<{ readonly deviceId: string; readonly event: DropEvent }>();
      const progressSignal = yield* Queue.sliding<void>(1);
      const sweepSignal = yield* Queue.sliding<void>(1);
      const hashJobs = yield* Queue.unbounded<{ readonly drop: DropRecord; readonly file: DropFileRecord }>();
      const drops = new Map<string, DropRecord>(db.loadAll().map((drop) => [drop.id, drop]));
      const dirty = new Set<DropRecord>();
      const hashing = new Map<DropFileRecord, Promise<string | null>>();
      let policy = DEFAULT_POLICY;
      let macName = "Mac";
      let macReady = false;

      const log = (level: "info" | "warn" | "error", kind: string, data: Record<string, unknown>, deviceId: string | null = null) =>
        activity.record({ at: Date.now(), source: "gateway", level, kind, deviceId, data });

      const tell = (message: ToApp) => {
        if (macReady) Effect.runSync(bridge.send(message));
      };

      const live = (drop: DropRecord) => drops.get(drop.id) === drop;
      const going = () => [...drops.values()].filter((drop) => !ended(drop));

      const announce = (drop: DropRecord) => {
        dirty.delete(drop);
        const value = wire(drop);
        PubSub.publishUnsafe(hub, { deviceId: drop.deviceId, event: { _tag: "Changed", drop: value } });
        tell({ t: "drop", drop: value });
      };

      const save = (drop: DropRecord) => {
        drop.updatedAt = Date.now();
        db.saveDrop(drop);
        announce(drop);
      };

      const progressed = (drop: DropRecord) => {
        drop.updatedAt = Date.now();
        dirty.add(drop);
        Queue.offerUnsafe(progressSignal, undefined);
      };

      const remove = (drop: DropRecord) => {
        drops.delete(drop.id);
        dirty.delete(drop);
        db.delete(drop.id);
        void files.removeDrop(drop.id);
        PubSub.publishUnsafe(hub, { deviceId: drop.deviceId, event: { _tag: "Removed", id: drop.id } });
        tell({ t: "dropRemoved", id: drop.id });
      };

      const retain = () => {
        const cutoff = Date.now() - RETAIN_MS;
        const finished = [...drops.values()].filter(ended).sort((left, right) => right.updatedAt - left.updatedAt);
        finished.forEach((drop, index) => {
          if (index >= MAX_FINISHED || drop.updatedAt < cutoff) remove(drop);
        });
      };

      const logEnd = (drop: DropRecord) =>
        activity.record({
          at: Date.now(),
          source: "gateway",
          level: drop.state === "failed" ? "warn" : "info",
          kind: `drop.${drop.state}`,
          deviceId: drop.deviceId,
          durationMs: Date.now() - (drop.startedAt ?? drop.createdAt),
          data: {
            direction: drop.incoming ? "toMac" : "fromMac",
            files: drop.files.length,
            bytes: drop.files.reduce((sum, file) => sum + file.done, 0),
            route: drop.route,
            error: drop.error,
          },
        });

      const deliver = (drop: DropRecord) =>
        tell({
          t: "dropReceived",
          id: drop.id,
          from: drop.from,
          files: drop.files.map((file) => ({ stored: `${drop.id}/${file.id}`, name: file.name, path: file.path, size: file.size })),
          ...(drop.dest === null ? {} : { dest: drop.dest }),
        });

      const finish = (drop: DropRecord, state: Ending, error: string | null = null) => {
        if (ended(drop)) return;
        drop.state = state;
        drop.error = error;
        save(drop);
        logEnd(drop);
        if (drop.incoming && state === "done" && drop.relay !== null) Effect.runFork(relayOut(drop, drop.relay));
        else if (drop.incoming && state === "done") deliver(drop);
        else if (drop.incoming) void files.removeDrop(drop.id);
        if (!drop.incoming && drop.source !== null) void files.removeDrop(drop.source);
        retain();
      };

      const move = (drop: DropRecord, state: Going) => {
        if (ended(drop) || drop.state === state) return;
        drop.state = state;
        if (state === "running") drop.startedAt ??= Date.now();
        save(drop);
      };

      const add = (drop: DropRecord) => {
        drops.set(drop.id, drop);
        db.insert(drop);
        announce(drop);
        if (ended(drop)) {
          logEnd(drop);
          retain();
        } else {
          Queue.offerUnsafe(sweepSignal, undefined);
        }
      };

      const busy = (deviceId: string): string | null => {
        const current = going();
        if (current.length >= MAX_ACTIVE.total) return "Vitals is busy with other drops. Try again in a moment.";
        if (current.filter((drop) => drop.deviceId === deviceId).length >= MAX_ACTIVE.device) {
          return `There are already ${String(MAX_ACTIVE.device)} drops going with this device. Wait for one to finish.`;
        }
        return null;
      };

      const issue = (drop: DropRecord): DropTicket => {
        const ticket = randomToken();
        const expiresAt = Date.now() + DROP_LIMITS.ticketMs;
        db.insertTicket(hashTicket(ticket), { dropId: drop.id, deviceId: drop.deviceId, expiresAt }, TICKETS_PER_DROP);
        return { ticket, expiresAt };
      };

      const hashOf = (drop: DropRecord, file: DropFileRecord): Promise<string | null> => {
        if (file.sha256 !== null) return Promise.resolve(file.sha256);
        const running = hashing.get(file);
        if (running !== undefined) return running;
        const origin = file.origin;
        if (origin === null) return Promise.resolve(null);
        const job = hashFile(origin, () => live(drop) && !ended(drop))
          .catch(() => null)
          .then((sha256) => {
            hashing.delete(file);
            if (sha256 !== null && live(drop)) {
              file.sha256 = sha256;
              db.saveFile(drop.id, file);
              progressed(drop);
            }
            return sha256;
          });
        hashing.set(file, job);
        return job;
      };

      const sweep = () => {
        const cutoff = Date.now() - DROP_LIMITS.idleMs;
        for (const drop of going()) {
          if (drop.updatedAt < cutoff) finish(drop, "failed", "Nothing moved for a day, so Vitals stopped this drop");
        }
        db.pruneTickets(Date.now());
        retain();
      };

      const sweepWhileGoing: Effect.Effect<void> = Effect.suspend(() =>
        going().length === 0
          ? Effect.void
          : Effect.sleep(SWEEP_EVERY).pipe(Effect.andThen(Effect.sync(sweep)), Effect.andThen(sweepWhileGoing)),
      );

      const strays = yield* Effect.promise(() => files.prepare(new Set(drops.keys())));
      if (strays > 0) log("info", "drop.strays", { removed: strays });
      for (const drop of drops.values()) {
        if (drop.incoming || ended(drop)) continue;
        if (drop.state === "asking") drop.state = "waiting";
        db.saveDrop(drop);
        for (const file of drop.files) if (file.sha256 === null) Queue.offerUnsafe(hashJobs, { drop, file });
      }
      sweep();
      if (going().length > 0) Queue.offerUnsafe(sweepSignal, undefined);

      const greet = Effect.gen(function* () {
        macReady = true;
        for (const drop of drops.values()) {
          tell({ t: "drop", drop: wire(drop) });
          if (drop.incoming && drop.state === "done" && (yield* Effect.promise(() => files.hasStaged(drop.id)))) deliver(drop);
        }
      });

      const sendFromMac = (to: ReadonlyArray<DeviceId>, list: ReadonlyArray<MacDropFile>, source: string | null = null, from: DropPeer | null = null) =>
        Effect.gen(function* () {
          const sizes = yield* Effect.promise(() => Promise.all(list.map((file) => files.originSize(file.origin))));
          const missing = list.find((_, index) => sizes[index] === null);
          const online = yield* connections.connectedDevices;
          for (const deviceId of new Set(to)) {
            const device = store.device(deviceId);
            if (device === null || device.revokedAt !== null) {
              log("warn", "drop.send.unknown", {}, deviceId);
              continue;
            }
            const refusal =
              device.platform === "web"
                ? `${device.name} is a browser, which can't receive files`
                : !device.scopes.includes("files")
                  ? `${device.name} isn't allowed to receive files`
                  : missing === undefined
                    ? busy(device.id)
                    : `${missing.name} is no longer on this Mac`;
            const now = Date.now();
            const drop = makeDrop({
              id: makeDropId(newId()),
              deviceId: device.id,
              incoming: false,
              from: from ?? { _tag: "Mac", name: macName },
              to: { _tag: "Device", deviceId: device.id, name: device.name },
              files: list.map((file, index) => fileRecord(index, file, sizes[index] ?? file.size, null, file.origin)),
              createdAt: now,
              state: refusal !== null ? "failed" : online.has(device.id) ? "asking" : "waiting",
              route: null,
              updatedAt: now,
              startedAt: null,
              error: refusal,
              dest: null,
              relay: null,
              source,
            });
            add(drop);
            if (refusal === null) for (const file of drop.files) Queue.offerUnsafe(hashJobs, { drop, file });
          }
        });

      const relayOut = (drop: DropRecord, to: DeviceId) =>
        sendFromMac(
          [to],
          drop.files.map((file) => ({ name: file.name, path: file.path, size: file.size, mime: file.mime, origin: files.staged(drop.id, file.id) })),
          drop.id,
          drop.from,
        );

      const decide = (id: string, accept: boolean) => {
        const drop = drops.get(id);
        if (drop === undefined || !drop.incoming || drop.state !== "asking") return;
        if (accept) move(drop, "running");
        else finish(drop, "declined");
      };

      const pause = (id: string, paused: boolean) => {
        const drop = drops.get(id);
        if (drop === undefined) return;
        if (paused && drop.state === "running") move(drop, "paused");
        if (!paused && drop.state === "paused") move(drop, "running");
      };

      const fromMac = (message: FromApp): Effect.Effect<void> => {
        switch (message.t) {
          case "hello":
            macName = message.mac.name;
            return greet;
          case "dropPolicy":
            return Effect.sync(() => {
              policy = message.policy;
            });
          case "dropSend":
            return sendFromMac(message.to, message.files);
          case "dropDecision":
            return Effect.sync(() => decide(message.id, message.accept));
          case "dropPause":
            return Effect.sync(() => pause(message.id, message.paused));
          case "dropCancel":
            return Effect.sync(() => {
              const drop = drops.get(message.id);
              if (drop !== undefined) finish(drop, "cancelled");
            });
          default:
            return Effect.void;
        }
      };

      const guarded = (effect: Effect.Effect<void>) =>
        effect.pipe(Effect.catchCause((cause) => Effect.sync(() => log("error", "drop.failed", { cause: Cause.pretty(cause).slice(0, 500) }))));

      const inbox = yield* bridge.subscribe;
      yield* Stream.fromSubscription(inbox).pipe(
        Stream.runForEach((message) => guarded(fromMac(message))),
        Effect.forkScoped,
      );

      const presence = yield* connections.presence;
      yield* Stream.fromSubscription(presence).pipe(
        Stream.runForEach(({ deviceId, online }) =>
          Effect.sync(() => {
            for (const drop of drops.values()) {
              if (drop.incoming || drop.deviceId !== deviceId) continue;
              if (online && drop.state === "waiting") move(drop, "asking");
              if (!online && drop.state === "asking") move(drop, "waiting");
            }
          }),
        ),
        Effect.forkScoped,
      );

      yield* Queue.take(progressSignal).pipe(
        Effect.andThen(Effect.sleep(PROGRESS_EVERY)),
        Effect.andThen(
          Effect.sync(() => {
            for (const drop of dirty) {
              db.saveDrop(drop);
              announce(drop);
            }
          }),
        ),
        Effect.forever,
        Effect.forkScoped,
      );

      yield* Queue.take(sweepSignal).pipe(Effect.andThen(sweepWhileGoing), Effect.forever, Effect.forkScoped);

      yield* Queue.take(hashJobs).pipe(
        Effect.flatMap(({ drop, file }) => (ended(drop) || file.sha256 !== null ? Effect.void : Effect.promise(() => hashOf(drop, file)))),
        Effect.forever,
        Effect.forkScoped,
      );

      const mine = (caller: DropCaller, id: string) =>
        Effect.suspend(() => {
          const drop = drops.get(id);
          return drop === undefined || drop.deviceId !== caller.deviceId ? Effect.fail(unavailable(GONE)) : Effect.succeed(drop);
        });

      const offer = (caller: DropCaller, input: DropOfferInput) =>
        Effect.gen(function* () {
          const refusal = busy(caller.deviceId);
          if (refusal !== null) return yield* Effect.fail(rejected(refusal));
          const bytes = input.files.reduce((sum, file) => sum + file.size, 0);
          const reserved = going()
            .filter((drop) => drop.incoming)
            .reduce((sum, drop) => sum + drop.files.reduce((left, file) => left + file.size - file.done, 0), 0);
          const free = yield* Effect.promise(() => files.freeBytes());
          if (free !== null && free < bytes + reserved) return yield* Effect.fail(rejected(`Your Mac needs ${formatBytes(bytes + reserved)} free for this`));
          const asks = !policy.autoAccept || bytes > policy.maxBytes || (caller.platform === "web" && policy.askWeb);
          const now = Date.now();
          const drop = makeDrop({
            id: makeDropId(newId()),
            deviceId: caller.deviceId,
            incoming: true,
            from: { _tag: "Device", deviceId: caller.deviceId, name: caller.name },
            to: { _tag: "Mac", name: macName },
            files: input.files.map((file, index) => fileRecord(index, file, file.size, file.sha256, null)),
            createdAt: now,
            state: asks ? "asking" : "running",
            route: null,
            updatedAt: now,
            startedAt: asks ? null : now,
            error: null,
            dest: input.dest ?? null,
            relay: input.relay ?? null,
            source: null,
          });
          yield* Effect.tryPromise({ try: () => files.ensure(drop.id), catch: () => rejected("The Mac could not get ready for this drop") });
          add(drop);
          return { drop: wire(drop), ticket: issue(drop) };
        });

      const pull = (caller: DropCaller, list: ReadonlyArray<MacDropFile>) =>
        Effect.gen(function* () {
          const refusal = busy(caller.deviceId);
          if (refusal !== null) return yield* Effect.fail(rejected(refusal));
          const now = Date.now();
          const drop = makeDrop({
            id: makeDropId(newId()),
            deviceId: caller.deviceId,
            incoming: false,
            from: { _tag: "Mac", name: macName },
            to: { _tag: "Device", deviceId: caller.deviceId, name: caller.name },
            files: list.map((file, index) => fileRecord(index, file, file.size, null, file.origin)),
            createdAt: now,
            state: "running",
            route: null,
            updatedAt: now,
            startedAt: now,
            error: null,
            dest: null,
            relay: null,
            source: null,
          });
          add(drop);
          for (const file of drop.files) Queue.offerUnsafe(hashJobs, { drop, file });
          return { drop: wire(drop), ticket: issue(drop) };
        });

      const accept = (caller: DropCaller, { id }: DropIdInput) =>
        Effect.flatMap(mine(caller, id), (drop): Effect.Effect<DropOffered, DropError> => {
          if (drop.incoming) return Effect.fail(rejected("Only the Mac can accept this drop"));
          if (ended(drop)) return Effect.fail(rejected(ENDED));
          if (drop.state === "asking" || drop.state === "waiting") move(drop, "running");
          return Effect.succeed({ drop: wire(drop), ticket: issue(drop) });
        });

      const decline = (caller: DropCaller, { id }: DropIdInput) =>
        Effect.flatMap(mine(caller, id), (drop): Effect.Effect<Drop, DropError> => {
          if (drop.incoming) return Effect.fail(rejected("Only the Mac can decline this drop"));
          if (drop.state === "running" || drop.state === "paused") return Effect.fail(rejected("That drop already started. Cancel it instead."));
          finish(drop, "declined");
          return Effect.succeed(wire(drop));
        });

      const cancel = (caller: DropCaller, { id }: DropIdInput) =>
        Effect.map(mine(caller, id), (drop) => {
          finish(drop, "cancelled");
          return wire(drop);
        });

      const ticket = (caller: DropCaller, { id }: DropIdInput) =>
        Effect.flatMap(mine(caller, id), (drop) => (ended(drop) ? Effect.fail(rejected(ENDED)) : Effect.succeed(issue(drop))));

      const received = (caller: DropCaller, input: DropReceivedInput) =>
        Effect.gen(function* () {
          const drop = yield* mine(caller, input.id);
          if (drop.incoming) return yield* Effect.fail(rejected("That drop goes to the Mac"));
          const file = drop.byId.get(input.fileId);
          if (file === undefined) return yield* Effect.fail(unavailable("That file is not in this drop"));
          if (drop.state === "done" || file.complete) return wire(drop);
          if (ended(drop)) return yield* Effect.fail(rejected(ENDED));
          if (drop.state === "asking" || drop.state === "waiting") return yield* Effect.fail(rejected("Accept the drop first"));
          if (input.sha256 !== null) {
            const expected = yield* Effect.promise(() => hashOf(drop, file));
            if (expected !== null && expected !== input.sha256) {
              file.parts.clear();
              file.done = 0;
              progressed(drop);
              return yield* Effect.fail(rejected(`${file.name} changed on the way. Download it again.`));
            }
          }
          markComplete(drop, file);
          return wire(drop);
        });

      const markComplete = (drop: DropRecord, file: DropFileRecord) => {
        file.complete = true;
        file.done = file.size;
        db.saveFile(drop.id, file);
        if (drop.files.every((entry) => entry.complete)) finish(drop, "done");
        else progressed(drop);
      };

      const settleFile = async (drop: DropRecord, file: DropFileRecord): Promise<"ok" | "damaged" | "stopped"> => {
        file.verifying = true;
        const keepGoing = () => live(drop) && !ended(drop);
        try {
          if (file.sha256 !== null) {
            const actual = await hashFile(files.part(drop.id, file.id), keepGoing).catch(() => null);
            if (!keepGoing()) return "stopped";
            if (actual !== file.sha256) {
              file.parts.clear();
              file.done = 0;
              await files.removePart(drop.id, file.id);
              db.saveFile(drop.id, file);
              progressed(drop);
              return "damaged";
            }
          }
          await files.publish(drop.id, file.id);
          if (!keepGoing()) return "stopped";
          markComplete(drop, file);
          return "ok";
        } catch {
          return "stopped";
        } finally {
          file.verifying = false;
        }
      };

      const done = (file: DropFileRecord) =>
        new Response(null, { status: 204, headers: { "x-vitals-done": String(file.done), "cache-control": "no-store" } });

      const damaged = (file: DropFileRecord) => problem(422, "checksum", `${file.name} arrived damaged. Send it again.`);

      const upload = async (request: Request, drop: DropRecord, file: DropFileRecord, route: DropRoute): Promise<Response> => {
        if (!drop.incoming) return problem(405, "direction", "This drop goes to this device", { allow: "GET, HEAD" });
        if (file.complete) return problem(409, "done", "That file is already on the Mac");
        if (file.verifying) return problem(409, "verifying", "That file is being checked");
        const refused = blocked(drop);
        if (refused !== null) return refused;
        const range = parseContentRange(request.headers.get("content-range"), file.size, PART);
        if (range === null) return problem(416, "range", "Content-Range must cover exactly one part of this file");
        drop.route = route;
        if (range._tag === "Empty") {
          if (file.sha256 !== null && file.sha256 !== EMPTY_SHA256) return damaged(file);
          await files.createEmpty(drop.id, file.id);
          if (!live(drop) || ended(drop)) return problem(410, "ended", ENDED);
          file.parts.add(0);
          markComplete(drop, file);
          return done(file);
        }
        const keepGoing = () => live(drop) && drop.state === "running";
        const result = await files.writePart(request.body, files.part(drop.id, file.id), range.start, range.length, keepGoing);
        if (!keepGoing()) return blocked(drop) ?? problem(410, "ended", ENDED);
        switch (result) {
          case "long":
          case "short":
            return problem(400, "length", "The body must be exactly the bytes named in Content-Range");
          case "full":
            return problem(507, "space", "The Mac ran out of space");
          case "broken":
          case "stopped":
            return problem(400, "interrupted", "That part did not arrive in full");
          case "ok":
            break;
        }
        if (!file.parts.has(range.index)) {
          file.parts.add(range.index);
          file.done += range.length;
        }
        db.saveFile(drop.id, file);
        if (file.complete || file.verifying || file.parts.size < partCount(file.size, PART)) {
          progressed(drop);
          return done(file);
        }
        const verdict = await settleFile(drop, file);
        if (verdict === "damaged") return damaged(file);
        if (verdict === "stopped") return blocked(drop) ?? problem(410, "ended", ENDED);
        return done(file);
      };

      const head = (drop: DropRecord, file: DropFileRecord): Response => {
        const headers: Record<string, string> = { "content-length": String(file.size), "cache-control": "no-store" };
        if (drop.incoming) headers["x-vitals-parts"] = [...file.parts].sort((left, right) => left - right).join(",");
        else headers["accept-ranges"] = "bytes";
        return new Response(null, { status: 200, headers });
      };

      const download = async (request: Request, drop: DropRecord, file: DropFileRecord, route: DropRoute): Promise<Response> => {
        if (drop.incoming) return problem(405, "direction", "This drop goes to the Mac", { allow: "PUT, HEAD" });
        const refused = blocked(drop);
        if (refused !== null) return refused;
        const origin = file.origin ?? "";
        if ((await files.originSize(origin)) !== file.size) {
          finish(drop, "failed", `${file.name} changed or moved on the Mac`);
          return problem(410, "changed", `${file.name} changed or moved on the Mac`);
        }
        const range = parseRange(request.headers.get("range"), file.size);
        if (range === null || (file.size === 0 && range._tag === "Slice")) {
          return problem(416, "range", "That range is not in this file", { "content-range": `bytes */${String(file.size)}` });
        }
        drop.route = route;
        const headers: Record<string, string> = {
          "content-type": file.mime ?? "application/octet-stream",
          "accept-ranges": "bytes",
          "cache-control": "no-store",
        };
        if (file.size === 0) return new Response(new Uint8Array(0), { status: 200, headers });
        const start = range._tag === "Slice" ? range.start : 0;
        const end = range._tag === "Slice" ? range.end : file.size - 1;
        const length = end - start + 1;
        headers["content-length"] = String(length);
        if (range._tag === "Slice") headers["content-range"] = `bytes ${String(start)}-${String(end)}/${String(file.size)}`;
        if (range._tag === "Slice" && start % PART === 0 && length === Math.min(PART, file.size - start) && !file.complete && !file.parts.has(start / PART)) {
          file.parts.add(start / PART);
          file.done = Math.min(file.size, file.done + length);
          progressed(drop);
        }
        const body = Bun.file(origin).slice(start, end + 1);
        return new Response(body, { status: range._tag === "Slice" ? 206 : 200, headers });
      };

      const serve = async (request: Request, route: DropRoute): Promise<Response> => {
        const match = DROP_PATH.exec(new URL(request.url).pathname);
        if (match === null) return problem(404, "not_found", "Not found");
        const [, dropId = "", fileId = ""] = match;
        const ticket = request.headers.get("authorization")?.match(/^Drop\s+(\S+)$/)?.[1];
        if (ticket === undefined) return problem(401, "credentials", "Send Authorization: Drop <ticket>");
        const grant = db.ticket(hashTicket(ticket));
        if (grant === null || grant.dropId !== dropId) return problem(401, "credentials", "That ticket is not for this drop");
        if (grant.expiresAt < Date.now()) return problem(401, "expired", "That ticket expired. Ask for a new one.");
        const device = store.device(grant.deviceId);
        if (device === null || device.revokedAt !== null || !device.scopes.includes("files")) {
          return problem(403, "scope", "This device needs the files scope");
        }
        const drop = drops.get(dropId);
        const file = drop?.byId.get(fileId);
        if (drop === undefined || file === undefined || drop.deviceId !== grant.deviceId) return problem(404, "not_found", GONE);
        switch (request.method) {
          case "PUT":
            return upload(request, drop, file, route);
          case "HEAD":
            return head(drop, file);
          case "GET":
            return download(request, drop, file, route);
          default:
            return problem(405, "method", "Use PUT, HEAD or GET", { allow: "PUT, HEAD, GET" });
        }
      };

      const handle = (request: Request, route: DropRoute): Promise<Response> =>
        serve(request, route).catch((error: unknown) => {
          log("error", "drop.http.failed", { method: request.method, error: String(error).slice(0, 300) });
          return problem(500, "internal", "Something went wrong on the Mac");
        });

      const watch = (caller: DropCaller) =>
        Stream.unwrap(
          Effect.gen(function* () {
            const subscription = yield* PubSub.subscribe(hub);
            const snapshot: DropEvent = {
              _tag: "Snapshot",
              drops: [...drops.values()]
                .filter((drop) => drop.deviceId === caller.deviceId)
                .sort((left, right) => right.createdAt - left.createdAt)
                .map(wire),
            };
            return Stream.concat(
              Stream.make(snapshot),
              Stream.fromSubscription(subscription).pipe(
                Stream.filter((entry) => entry.deviceId === caller.deviceId),
                Stream.map((entry) => entry.event),
              ),
            );
          }),
        );

      return DropStore.of({ watch, offer, accept, pull, decline, cancel, ticket, received, handle });
    }),
  );
