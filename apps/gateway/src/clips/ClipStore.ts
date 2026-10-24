import type { Database } from "bun:sqlite";
import { closeSync, openSync, writeSync } from "node:fs";
import { rename } from "node:fs/promises";

import {
  type Clip,
  type ClipChunk,
  type ClipEvent,
  type ClipFileName,
  type ClipPlacement,
  type ClipPolicy,
  type ClipSendBegin,
  type ClipSendBegun,
  type ClipSendChunk,
  type ClipSendFinish,
  type ClipsPinInput,
  type ClipsPutInput,
  type ClipsPutResult,
  type ClipsReadInput,
  type ClipsRemoveInput,
  type DeviceId,
  type MacClip,
  CLIP_LIMITS,
  ClipId,
  CommandRejected,
  Unavailable,
  UploadId,
} from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Cause from "effect/Cause";
import * as Context from "effect/Context";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Queue from "effect/Queue";
import * as Schedule from "effect/Schedule";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Bridge, ask } from "../bridge/Bridge.ts";
import { GatewayConfig } from "../config.ts";
import { type ClipRecord, ClipDb, expired, isTextKind } from "./ClipDb.ts";
import { clipFiles, extensionFor, hashFile } from "./ClipFiles.ts";

/** Who is calling, for ownership checks and the activity log. */
export interface ClipCaller {
  readonly deviceId: DeviceId;
  readonly name: string;
  readonly connectionId: string;
}

type ClipError = Unavailable | CommandRejected;

export class ClipStore extends Context.Service<
  ClipStore,
  {
    readonly watch: Stream.Stream<ClipEvent>;
    readonly read: (caller: ClipCaller, input: ClipsReadInput) => Effect.Effect<ClipChunk, ClipError>;
    readonly pin: (caller: ClipCaller, input: ClipsPinInput) => Effect.Effect<Clip, Unavailable>;
    readonly remove: (caller: ClipCaller, input: ClipsRemoveInput) => Effect.Effect<void, Unavailable>;
    readonly begin: (caller: ClipCaller, input: ClipSendBegin) => Effect.Effect<ClipSendBegun, CommandRejected>;
    readonly chunk: (caller: ClipCaller, input: ClipSendChunk) => Effect.Effect<{ readonly received: number }, CommandRejected>;
    readonly finish: (caller: ClipCaller, input: ClipSendFinish) => Effect.Effect<Clip, CommandRejected>;
    readonly put: (caller: ClipCaller, input: ClipsPutInput) => Effect.Effect<ClipsPutResult, ClipError>;
  }
>()("@vitals/gateway/ClipStore") {}

const DAY_MS = 86_400_000;
const IDLE_MS = 10 * 60_000;
const STRAY_GRACE_MS = 60_000;
const MAX_UPLOADS = { device: 4, total: 16 } as const;
/** JSON bytes in the first watch frame, under the 1 MB frame cap with room for the RPC envelope. */
const SNAPSHOT_BUDGET = 900 * 1024;
const MATERIALIZE_TIMEOUT = "10 minutes";
const PUT_TIMEOUT = "2 minutes";

const GONE = "That clip is gone from the Mac";
const HISTORY_OFF = "Clipboard history is off on the Mac";

const makeClipId = Schema.decodeUnknownSync(ClipId);
const makeUploadId = Schema.decodeUnknownSync(UploadId);

const rejected = (message: string) => new CommandRejected({ message });
const unavailable = (message: string) => new Unavailable({ message });

interface Upload {
  readonly id: UploadId;
  readonly caller: ClipCaller;
  readonly meta: ClipSendBegin;
  readonly path: string;
  readonly startedAt: number;
  readonly chunks: Set<number>;
  /** Open while chunks may still arrive; null once closed so a reused descriptor is never written. */
  fd: number | null;
  received: number;
  touchedAt: number;
  finishing: boolean;
}

interface Download {
  readonly caller: ClipCaller;
  readonly startedAt: number;
  bytes: number;
  touchedAt: number;
}

/** Bytes behind a clip, read one chunk at a time. */
interface Content {
  readonly total: number;
  readonly slice: (start: number, end: number) => Promise<Uint8Array>;
}

/** Cuts text to the preview length without leaving half a surrogate pair. */
const preview = (text: string): string => {
  const cut = text.slice(0, CLIP_LIMITS.previewText);
  return /[\uD800-\uDBFF]$/.test(cut) ? cut.slice(0, -1) : cut;
};

/** What phones see. Long text is cut to a preview so events stay small; `clips.read` has the rest. */
const toWire = (record: ClipRecord): Clip => {
  const clip: Clip = {
    id: record.id,
    kind: record.kind,
    at: record.at,
    deviceId: record.deviceId,
    source: record.source,
    text: record.text,
    truncated: record.truncated,
    name: record.name,
    mime: record.mime,
    bytes: record.bytes,
    files: record.files,
    thumb: record.thumb,
    pinned: record.pinned,
  };
  const text = record.text;
  if (text === null || text.length <= CLIP_LIMITS.previewText) return clip;
  return { ...clip, text: preview(text), truncated: true, bytes: record.stored === null ? Buffer.byteLength(text) : record.bytes };
};

/** A Downloads subfolder name the Mac can use as is: no separators, control characters, or leading dots. */
const safeFolder = (folder: string | null): string | null => {
  const printable = [...(folder ?? "")].map((char) => (char < " " || "/\\:".includes(char) ? "-" : char)).join("");
  const cleaned = printable.replace(/^[.\s]+/, "").trim();
  return cleaned.length === 0 ? null : cleaned;
};

const closeUpload = (upload: Upload): void => {
  if (upload.fd === null) return;
  try {
    closeSync(upload.fd);
  } catch {
    // Already closed; nothing to release.
  }
  upload.fd = null;
};

export const layer = (database: Database) =>
  Layer.effect(
    ClipStore,
    Effect.gen(function* () {
      const config = yield* GatewayConfig;
      const bridge = yield* Bridge;
      const activity = yield* ActivityLog;
      const scope = yield* Effect.scope;
      const db = new ClipDb(database);
      const files = clipFiles(config.dataDir);
      const hub = yield* PubSub.unbounded<ClipEvent>();
      const statsDirty = yield* Queue.sliding<void>(1);
      const uploads = new Map<string, Upload>();
      const downloads = new Map<string, Download>();
      const materializing = new Map<string, Deferred.Deferred<ClipRecord, Unavailable>>();
      /** Unknown until the Mac sends it after hello. Until then Mac clips stay hidden and age pruning waits. */
      let policy: ClipPolicy | null = null;

      const strays = yield* Effect.promise(() => files.prepare(db.storedNames(), STRAY_GRACE_MS));
      if (strays > 0) activity.record({ at: Date.now(), source: "gateway", level: "info", kind: "clip.strays", data: { removed: strays } });

      const note = (caller: ClipCaller, kind: string, data: Record<string, unknown>, durationMs: number | null = null) =>
        activity.record({
          at: Date.now(),
          source: "gateway",
          level: "info",
          kind,
          deviceId: caller.deviceId,
          connectionId: caller.connectionId,
          durationMs,
          data,
        });

      /** One summary row per transfer, instead of a frame row per chunk. */
      const transfer = (
        kind: "clip.download" | "clip.upload",
        from: { readonly caller: ClipCaller; readonly startedAt: number },
        data: { readonly ok: boolean; readonly bytes: number } & Record<string, unknown>,
      ) =>
        activity.record({
          at: Date.now(),
          source: "gateway",
          level: data.ok ? "info" : "warn",
          kind,
          deviceId: from.caller.deviceId,
          connectionId: from.caller.connectionId,
          durationMs: Date.now() - from.startedAt,
          data,
        });

      const historyOn = () => policy?.enabled === true;
      const visible = (clip: ClipRecord) => clip.deviceId !== null || historyOn();
      const changed = () => Queue.offerUnsafe(statsDirty, undefined);

      const announce = (tag: "Added" | "Updated", clip: ClipRecord) =>
        visible(clip) ? Effect.asVoid(PubSub.publish(hub, { _tag: tag, clip: toWire(clip) })) : Effect.void;

      /** Newest clips that fit the frame budget. Thumbnails are dropped first, then older clips. */
      const snapshot = (): ClipEvent => {
        const enabled = historyOn();
        const clips: Array<Clip> = [];
        let used = 0;
        for (const record of db.recent(CLIP_LIMITS.snapshot, enabled)) {
          const full = toWire(record);
          const bare = { ...full, thumb: null };
          const fits = [full, bare].find((clip) => used + Buffer.byteLength(JSON.stringify(clip)) + 1 <= SNAPSHOT_BUDGET);
          if (fits === undefined) break;
          clips.push(fits);
          used += Buffer.byteLength(JSON.stringify(fits)) + 1;
        }
        return { _tag: "Snapshot", enabled, keepDays: policy?.keepDays ?? null, clips };
      };

      const discard = (name: string | null) => (name === null ? Effect.void : Effect.promise(() => files.remove(name)));

      const drop = (clips: ReadonlyArray<ClipRecord>) =>
        Effect.gen(function* () {
          if (clips.length === 0) return;
          db.delete(clips.map((clip) => clip.id));
          for (const clip of clips) yield* discard(clip.stored);
          yield* PubSub.publish(hub, { _tag: "Removed", ids: clips.map((clip) => clip.id) });
          changed();
        });

      const prune = Effect.suspend(() =>
        drop(expired(db.unpinnedOldestFirst(), db.stats(), policy === null ? null : Date.now() - policy.keepDays * DAY_MS)),
      );

      const store = (clip: ClipRecord) =>
        Effect.gen(function* () {
          db.insert(clip);
          yield* announce("Added", clip);
          changed();
          yield* prune;
        });

      /** A copy on the Mac. A repeat of an earlier clip bumps that one instead of adding a twin. */
      const addMacClip = (mac: MacClip) =>
        Effect.gen(function* () {
          // History is off: keep nothing, but never delete a file an existing row still points at.
          if (!historyOn()) return yield* discard(mac.stored !== null && db.storedNames().has(mac.stored) ? null : mac.stored);
          if (db.get(mac.id) !== null) return;
          const stored = mac.stored;
          const file = stored === null ? null : yield* Effect.promise(() => files.inspect(stored));
          if (stored !== null && file === null) {
            activity.record({ at: Date.now(), source: "gateway", level: "warn", kind: "clip.missing", data: { kind: mac.kind } });
            return;
          }
          const clip: ClipRecord = { ...mac, deviceId: null, pinned: false, bytes: file?.bytes ?? mac.bytes, sha256: file?.sha256 ?? null };
          const twin = db.findDuplicate(clip);
          if (twin === null) return yield* store(clip);
          if (clip.stored !== twin.stored) yield* discard(clip.stored);
          // A file or folder may have changed since it was cloned or zipped, so the next download redoes it.
          const stale = twin.origin !== null && twin.stored !== null;
          if (stale) yield* discard(twin.stored);
          const at = Math.max(twin.at, clip.at);
          const bumped: ClipRecord = stale ? { ...twin, at, stored: null, bytes: clip.bytes, files: clip.files } : { ...twin, at };
          db.update(bumped);
          yield* announce("Updated", bumped);
          changed();
        });

      const setPolicy = (next: ClipPolicy) =>
        Effect.gen(function* () {
          const flipped = historyOn() !== next.enabled;
          policy = next;
          if (flipped) yield* PubSub.publish(hub, snapshot());
          changed();
          yield* prune;
        });

      const guarded = <A, E>(kind: string, effect: Effect.Effect<A, E>) =>
        effect.pipe(
          Effect.asVoid,
          Effect.catchCause((cause) =>
            Effect.sync(() =>
              activity.record({ at: Date.now(), source: "gateway", level: "error", kind, data: { cause: Cause.pretty(cause).slice(0, 500) } }),
            ),
          ),
        );

      // Subscribed while the layer builds: the Mac sends its policy right after hello.
      const inbox = yield* bridge.subscribe;
      yield* Stream.fromSubscription(inbox).pipe(
        Stream.runForEach((message) => {
          switch (message.t) {
            case "clip":
              return guarded("clip.failed", addMacClip(message.clip));
            case "clipPolicy":
              return guarded("clip.failed", setPolicy(message.policy));
            case "clipClear":
              return guarded("clip.failed", Effect.suspend(() => drop(db.unpinnedOldestFirst())));
            default:
              return Effect.void;
          }
        }),
        Effect.forkScoped,
      );

      yield* Queue.take(statsDirty).pipe(
        Effect.andThen(Effect.sleep("1 second")),
        Effect.andThen(Effect.suspend(() => bridge.send({ t: "clipStats", stats: db.stats() }))),
        Effect.forever,
        Effect.forkScoped,
      );

      const abandon = (upload: Upload, reason: string) =>
        Effect.gen(function* () {
          if (uploads.get(upload.id) !== upload) return;
          uploads.delete(upload.id);
          closeUpload(upload);
          yield* Effect.promise(() => files.removePart(upload.id));
          transfer("clip.upload", upload, { ok: false, bytes: upload.received, kind: upload.meta.kind, reason });
        });

      const sweep = Effect.gen(function* () {
        const cutoff = Date.now() - IDLE_MS;
        for (const upload of uploads.values()) {
          if (!upload.finishing && upload.touchedAt < cutoff) yield* abandon(upload, "abandoned");
        }
        for (const [key, download] of downloads) {
          if (download.touchedAt >= cutoff) continue;
          downloads.delete(key);
          transfer("clip.download", download, { ok: false, bytes: download.bytes, reason: "abandoned" });
        }
      });

      yield* guarded("clip.prune.failed", prune).pipe(Effect.repeat(Schedule.spaced("1 hour")), Effect.forkScoped);
      yield* guarded("clip.sweep.failed", sweep).pipe(Effect.repeat(Schedule.spaced("1 minute")), Effect.forkScoped);

      const reachable = (id: ClipId) =>
        Effect.suspend(() => {
          const clip = db.get(id);
          if (clip === null) return Effect.fail(unavailable(GONE));
          if (!visible(clip)) return Effect.fail(unavailable(HISTORY_OFF));
          return Effect.succeed(clip);
        });

      /** Records where the Mac put a cloned file or zipped folder. */
      const adopt = (id: ClipId, result: { readonly stored: ClipFileName; readonly files: number | null }) =>
        Effect.gen(function* () {
          const bytes = yield* Effect.promise(() => files.size(result.stored));
          if (bytes === null) return yield* Effect.fail(unavailable("Vitals could not prepare that file"));
          const current = db.get(id);
          if (current === null) {
            yield* discard(result.stored);
            return yield* Effect.fail(unavailable(GONE));
          }
          if (current.stored !== null && current.stored !== result.stored) yield* discard(current.stored);
          const ready: ClipRecord = { ...current, stored: result.stored, bytes, files: result.files };
          db.update(ready);
          yield* announce("Updated", ready);
          changed();
          return ready;
        });

      /**
       * Asks the Mac to clone a copied file or zip a copied folder into `clips/`. Concurrent callers
       * share one request, and it runs in the service scope so a reader hanging up doesn't cancel it.
       */
      const materialize = (clip: ClipRecord) =>
        Effect.suspend((): Effect.Effect<ClipRecord, Unavailable> => {
          const running = materializing.get(clip.id);
          if (running !== undefined) return Deferred.await(running);
          const origin = clip.origin;
          const kind = clip.kind;
          if (origin === null || (kind !== "file" && kind !== "folder")) return Effect.fail(unavailable("That clip has nothing to download"));
          const deferred = Deferred.makeUnsafe<ClipRecord, Unavailable>();
          materializing.set(clip.id, deferred);
          const work = ask(bridge, { _tag: "ClipMaterialize", id: clip.id, kind, origin }, MATERIALIZE_TIMEOUT).pipe(
            Effect.flatMap((result) => adopt(clip.id, result)),
            Deferred.into(deferred),
            Effect.ensuring(Effect.sync(() => materializing.delete(clip.id))),
          );
          return Effect.andThen(Effect.forkIn(work, scope), Deferred.await(deferred));
        });

      const contentOf = (clip: ClipRecord): Effect.Effect<Content, Unavailable> =>
        Effect.gen(function* () {
          const stored = clip.stored;
          if (stored !== null) {
            const path = files.path(stored);
            const total = yield* Effect.promise(() => files.size(stored));
            if (path === null || total === null) return yield* Effect.fail(unavailable(GONE));
            return { total, slice: (start, end) => Bun.file(path).slice(start, end).bytes() };
          }
          if (clip.text !== null && clip.origin === null) {
            const bytes = Buffer.from(clip.text);
            return { total: bytes.length, slice: async (start, end) => bytes.subarray(start, end) };
          }
          return yield* contentOf(yield* materialize(clip));
        });

      const read = (caller: ClipCaller, { id, offset }: ClipsReadInput) => {
        const key = `${caller.connectionId}/${id}`;
        return Effect.gen(function* () {
          const content = yield* contentOf(yield* reachable(id));
          if (offset > content.total || (offset === content.total && content.total > 0)) {
            return yield* Effect.fail(rejected("That part of the clip does not exist"));
          }
          const end = Math.min(content.total, offset + CLIP_LIMITS.chunkBytes);
          const bytes = yield* Effect.tryPromise({ try: () => content.slice(offset, end), catch: () => unavailable(GONE) });
          const now = Date.now();
          const progress = (offset === 0 ? undefined : downloads.get(key)) ?? { caller, startedAt: now, bytes: 0, touchedAt: now };
          progress.bytes += bytes.length;
          progress.touchedAt = now;
          const done = end >= content.total;
          if (done) {
            downloads.delete(key);
            transfer("clip.download", progress, { ok: true, bytes: progress.bytes, clipId: id });
          } else {
            downloads.set(key, progress);
          }
          return { data: Buffer.from(bytes).toString("base64"), offset, total: content.total, done };
        }).pipe(
          Effect.tapError((error) =>
            Effect.sync(() => {
              const progress = downloads.get(key);
              downloads.delete(key);
              transfer("clip.download", progress ?? { caller, startedAt: Date.now() }, {
                ok: false,
                bytes: progress?.bytes ?? 0,
                clipId: id,
                reason: error.message,
              });
            }),
          ),
        );
      };

      const pin = (caller: ClipCaller, { id, pinned }: ClipsPinInput) =>
        Effect.gen(function* () {
          const next = { ...(yield* reachable(id)), pinned };
          db.update(next);
          yield* announce("Updated", next);
          changed();
          note(caller, "clip.pinned", { clipId: id, pinned });
          return toWire(next);
        });

      const remove = (caller: ClipCaller, { id }: ClipsRemoveInput) =>
        Effect.gen(function* () {
          const clip = yield* reachable(id);
          yield* drop([clip]);
          note(caller, "clip.removed", { clipId: id, kind: clip.kind });
        });

      const sendText = (caller: ClipCaller, meta: ClipSendBegin, kind: "text" | "link") =>
        Effect.gen(function* () {
          const text = meta.text;
          if (text === null || text.trim().length === 0) return yield* Effect.fail(rejected("There is no text to send"));
          if (meta.bytes !== 0) return yield* Effect.fail(rejected("Text is sent inline, so bytes must be 0"));
          const now = Date.now();
          const clip: ClipRecord = {
            id: makeClipId(newId()),
            kind,
            at: now,
            deviceId: caller.deviceId,
            source: caller.name,
            text,
            truncated: false,
            name: meta.name,
            mime: meta.mime,
            bytes: 0,
            files: null,
            thumb: null,
            pinned: false,
            stored: null,
            origin: null,
            sha256: null,
          };
          yield* store(clip);
          transfer("clip.upload", { caller, startedAt: now }, { ok: true, bytes: Buffer.byteLength(text), kind, clipId: clip.id });
          return { uploadId: makeUploadId(newId()), clip: toWire(clip) };
        });

      /** Opens an upload. Checks and registration happen in one synchronous step so limits can't be raced. */
      const openUpload = (caller: ClipCaller, meta: ClipSendBegin) =>
        Effect.suspend((): Effect.Effect<ClipSendBegun, CommandRejected> => {
          if (meta.bytes === 0) return Effect.fail(rejected("That file is empty"));
          if (meta.kind === "image" && meta.mime !== null && !meta.mime.startsWith("image/")) {
            return Effect.fail(rejected("That file is not an image"));
          }
          if (uploads.size >= MAX_UPLOADS.total) return Effect.fail(rejected("The Mac is busy with other uploads. Try again in a moment."));
          const mine = [...uploads.values()].filter((upload) => upload.caller.deviceId === caller.deviceId).length;
          if (mine >= MAX_UPLOADS.device) {
            return Effect.fail(rejected(`This device already has ${String(MAX_UPLOADS.device)} uploads going. Wait for one to finish.`));
          }
          const id = makeUploadId(newId());
          const path = files.part(id);
          let fd: number;
          try {
            fd = openSync(path, "w", 0o600);
          } catch {
            return Effect.fail(rejected("The Mac could not start the upload"));
          }
          const now = Date.now();
          uploads.set(id, { id, caller, meta, path, startedAt: now, chunks: new Set(), fd, received: 0, touchedAt: now, finishing: false });
          return Effect.succeed({ uploadId: id, clip: null });
        });

      const begin = (caller: ClipCaller, meta: ClipSendBegin) =>
        isTextKind(meta.kind) ? sendText(caller, meta, meta.kind) : openUpload(caller, meta);

      const owned = (caller: ClipCaller, uploadId: UploadId): Upload | CommandRejected => {
        const upload = uploads.get(uploadId);
        if (upload === undefined) return rejected("That upload is not open. Send the file again.");
        if (upload.caller.deviceId !== caller.deviceId) return rejected("That upload belongs to another device");
        if (upload.finishing || upload.fd === null) return rejected("That upload is already finishing");
        return upload;
      };

      /** Writes one chunk at its offset. Chunks may arrive in any order; a repeat is harmless. */
      const chunk = (caller: ClipCaller, { uploadId, offset, data }: ClipSendChunk) =>
        Effect.suspend((): Effect.Effect<{ readonly received: number }, CommandRejected> => {
          const upload = owned(caller, uploadId);
          if (upload instanceof CommandRejected) return Effect.fail(upload);
          const size = CLIP_LIMITS.chunkBytes;
          if (offset % size !== 0) return Effect.fail(rejected("Each part must start on a 512 KB boundary"));
          if (offset >= upload.meta.bytes) return Effect.fail(rejected("That part is past the end of the file"));
          const bytes = Buffer.from(data, "base64");
          const expected = Math.min(size, upload.meta.bytes - offset);
          if (bytes.length !== expected) {
            return Effect.fail(rejected(`That part should be ${String(expected)} bytes, not ${String(bytes.length)}`));
          }
          try {
            writeSync(upload.fd ?? -1, bytes, 0, bytes.length, offset);
          } catch {
            return Effect.fail(rejected("The Mac could not save that part"));
          }
          if (!upload.chunks.has(offset / size)) {
            upload.chunks.add(offset / size);
            upload.received += bytes.length;
          }
          upload.touchedAt = Date.now();
          return Effect.succeed({ received: upload.received });
        });

      const complete = (upload: Upload) =>
        Effect.gen(function* () {
          const sha256 = yield* Effect.tryPromise({ try: () => hashFile(upload.path), catch: () => rejected("The Mac could not read the upload") });
          if (upload.meta.sha256 !== null && sha256 !== upload.meta.sha256) {
            yield* abandon(upload, "checksum");
            return yield* Effect.fail(rejected("The file changed on the way. Send it again."));
          }
          const id = makeClipId(newId());
          const stored = `${id}.${extensionFor(upload.meta.name, upload.meta.mime)}`;
          const target = files.path(stored);
          if (target === null) return yield* Effect.fail(rejected("The Mac could not name that file"));
          yield* Effect.tryPromise({ try: () => rename(upload.path, target), catch: () => rejected("The Mac could not save the file") });
          uploads.delete(upload.id);
          const clip: ClipRecord = {
            id,
            kind: upload.meta.kind,
            at: Date.now(),
            deviceId: upload.caller.deviceId,
            source: upload.caller.name,
            text: null,
            truncated: false,
            name: upload.meta.name,
            mime: upload.meta.mime,
            bytes: upload.meta.bytes,
            files: null,
            thumb: null,
            pinned: false,
            stored,
            origin: null,
            sha256,
          };
          yield* store(clip);
          transfer("clip.upload", upload, { ok: true, bytes: upload.received, kind: clip.kind, clipId: id });
          return toWire(clip);
        }).pipe(Effect.tapError(() => abandon(upload, "failed")));

      const finish = (caller: ClipCaller, { uploadId }: ClipSendFinish) =>
        Effect.suspend((): Effect.Effect<Clip, CommandRejected> => {
          const upload = owned(caller, uploadId);
          if (upload instanceof CommandRejected) return Effect.fail(upload);
          if (upload.received !== upload.meta.bytes) return Effect.fail(rejected("Part of the file has not arrived yet"));
          upload.finishing = true;
          closeUpload(upload);
          return complete(upload);
        });

      const put = (caller: ClipCaller, input: ClipsPutInput) =>
        Effect.gen(function* () {
          const started = Date.now();
          const items: Array<ClipPlacement> = [];
          for (const id of input.ids) {
            const found = yield* reachable(id);
            const clip = found.stored === null && found.origin !== null ? yield* materialize(found) : found;
            items.push({ kind: clip.kind, stored: clip.stored, text: clip.text, name: clip.name, mime: clip.mime });
          }
          const folder = input.to === "downloads" ? safeFolder(input.folder) : null;
          const { placed } = yield* ask(bridge, { _tag: "ClipPut", items, to: input.to, folder, deviceName: caller.name }, PUT_TIMEOUT);
          note(caller, "clip.put", { count: items.length, placed, to: input.to }, Date.now() - started);
          return { placed };
        });

      const watch = Stream.unwrap(
        Effect.gen(function* () {
          const subscription = yield* PubSub.subscribe(hub);
          return Stream.concat(Stream.make(snapshot()), Stream.fromSubscription(subscription));
        }),
      );

      return ClipStore.of({ watch, read, pin, remove, begin, chunk, finish, put });
    }),
  );
