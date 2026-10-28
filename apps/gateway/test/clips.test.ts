import { afterEach, describe, expect, test } from "bun:test";
import { randomBytes } from "node:crypto";
import { existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { type MacClip, CLIP_LIMITS, ClipId, DeviceId } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { type Gateway, adminOp, pairDevice, startGateway, withClient } from "./harness.ts";

const clipId = Schema.decodeUnknownSync(ClipId);
const deviceIdOf = Schema.decodeUnknownSync(DeviceId);
const DAY = 86_400_000;
const CHUNK = CLIP_LIMITS.chunkBytes;

let gateway: Gateway | null = null;

afterEach(async () => {
  await gateway?.stop();
  gateway = null;
});

const started = async () => {
  gateway = await startGateway();
  return gateway;
};

/** A paired phone that may read clipboard history. */
const clipboardPhone = async (target: Gateway) => {
  const paired = await pairDevice(target);
  await adminOp(target.app, { _tag: "SetScopes", deviceId: deviceIdOf(paired.deviceId), scopes: ["read", "operate", "clipboard"] });
  return paired;
};

const macClip = (id: string, fields: Partial<MacClip> = {}): MacClip => ({
  id: clipId(id),
  kind: "text",
  at: Date.now(),
  source: "Terminal",
  text: "git status",
  truncated: false,
  name: null,
  mime: null,
  bytes: 0,
  files: null,
  thumb: null,
  stored: null,
  origin: null,
  ...fields,
});

const historyOn = async (target: Gateway, keepDays = 7) => {
  target.app.emit({ t: "clipPolicy", policy: { enabled: true, keepDays } });
  await Bun.sleep(50);
};

const sha256 = (bytes: Uint8Array) => new Bun.CryptoHasher("sha256").update(bytes).digest("hex");
const base64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64");

describe("clips", () => {
  test("watch starts with a Snapshot, then a Mac copy arrives as Added", async () => {
    const target = await started();
    const { token } = await clipboardPhone(target);
    await historyOn(target);
    const events = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        yield* Effect.sync(() => setTimeout(() => target.app.emit({ t: "clip", clip: macClip("mac-text-0001") }), 150));
        return yield* client["clips.watch"]({}).pipe(Stream.take(2), Stream.runCollect);
      }),
    );
    const [first, second] = [...events];
    expect(first).toEqual({ _tag: "Snapshot", enabled: true, keepDays: 7, clips: [] });
    expect(second?._tag === "Added" ? second.clip : null).toMatchObject({ id: "mac-text-0001", deviceId: null, pinned: false, text: "git status" });
  });

  test("sending text stores it right away as the phone's clip", async () => {
    const target = await started();
    const { token, deviceId } = await clipboardPhone(target);
    const { begun, chunk } = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const begun = yield* client["clips.send.begin"]({ kind: "text", name: null, mime: null, bytes: 0, sha256: null, text: "hello mac" });
        const id = begun.clip?.id ?? clipId("missing-0000");
        return { begun, chunk: yield* client["clips.read"]({ id, offset: 0 }) };
      }),
    );
    expect(begun.clip).toMatchObject({ kind: "text", text: "hello mac", deviceId, source: "Pixel 9" });
    expect(Buffer.from(chunk.data, "base64").toString()).toBe("hello mac");
    expect(chunk.done).toBe(true);
  });

  test("an image uploaded out of order reads back byte for byte", async () => {
    const target = await started();
    const { token } = await clipboardPhone(target);
    const image = new Uint8Array(randomBytes(CHUNK * 2 + 12_345));
    const { clip, received, data } = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const { uploadId } = yield* client["clips.send.begin"]({
          kind: "image",
          name: "Photo.PNG",
          mime: "image/png",
          bytes: image.length,
          sha256: sha256(image),
          text: null,
        });
        const send = (offset: number) => client["clips.send.chunk"]({ uploadId, offset, data: base64(image.subarray(offset, offset + CHUNK)) });
        const acks = yield* Effect.all([CHUNK * 2, CHUNK, 0, CHUNK].map(send), { concurrency: 4 });
        const clip = yield* client["clips.send.finish"]({ uploadId });
        const parts: Array<Buffer> = [];
        for (let offset = 0; ; ) {
          const part = yield* client["clips.read"]({ id: clip.id, offset });
          parts.push(Buffer.from(part.data, "base64"));
          offset += parts.at(-1)?.length ?? 0;
          if (part.done) break;
        }
        return { clip, received: Math.max(...acks.map((ack) => ack.received)), data: Buffer.concat(parts) };
      }),
    );
    expect(received).toBe(image.length);
    expect(Buffer.compare(data, image)).toBe(0);
    expect(clip).toMatchObject({ kind: "image", bytes: image.length, name: "Photo.PNG" });
    expect(existsSync(join(target.dataDir, "clips", `${clip.id}.png`))).toBe(true);
  });

  test("an upload whose sha256 doesn't match is rejected and discarded", async () => {
    const target = await started();
    const { token } = await clipboardPhone(target);
    const bytes = new Uint8Array(randomBytes(64));
    const { error, uploadId } = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const { uploadId } = yield* client["clips.send.begin"]({ kind: "file", name: "a.bin", mime: null, bytes: 64, sha256: "0".repeat(64), text: null });
        yield* client["clips.send.chunk"]({ uploadId, offset: 0, data: base64(bytes) });
        return { uploadId, error: yield* Effect.flip(client["clips.send.finish"]({ uploadId })) };
      }),
    );
    expect(error._tag).toBe("CommandRejected");
    expect(existsSync(join(target.dataDir, "clips", "incoming", `${uploadId}.part`))).toBe(false);
  });

  test("only the device that began an upload may add to it, and only on chunk boundaries", async () => {
    const target = await started();
    const owner = await clipboardPhone(target);
    const other = await clipboardPhone(target);
    const begun = await withClient(target, owner.token, (client) =>
      Effect.gen(function* () {
        const begun = yield* client["clips.send.begin"]({ kind: "file", name: "notes.txt", mime: "text/plain", bytes: CHUNK + 10, sha256: null, text: null });
        const misaligned = yield* Effect.flip(client["clips.send.chunk"]({ uploadId: begun.uploadId, offset: 1, data: base64(new Uint8Array(10)) }));
        return { uploadId: begun.uploadId, misaligned };
      }),
    );
    const stranger = await withClient(target, other.token, (client) =>
      Effect.flip(client["clips.send.chunk"]({ uploadId: begun.uploadId, offset: CHUNK, data: base64(new Uint8Array(10)) })),
    );
    expect(begun.misaligned._tag).toBe("CommandRejected");
    expect(stranger).toMatchObject({ _tag: "CommandRejected", message: "That upload belongs to another device" });
  });

  test("retention drops old unpinned clips with their files and keeps pinned ones", async () => {
    const target = await started();
    const { token } = await clipboardPhone(target);
    await historyOn(target, 90);
    const old = Date.now() - 10 * DAY;
    for (const id of ["mac-old-keep", "mac-old-drop"]) {
      writeFileSync(join(target.dataDir, "clips", `${id}.png`), randomBytes(32));
      target.app.emit({ t: "clip", clip: macClip(id, { kind: "image", at: old, text: null, stored: `${id}.png`, bytes: 32, mime: "image/png" }) });
    }
    await Bun.sleep(150);
    await withClient(target, token, (client) => client["clips.pin"]({ id: clipId("mac-old-keep"), pinned: true }));
    await historyOn(target, 1);
    await Bun.sleep(100);
    const [snapshot] = await withClient(target, token, (client) => client["clips.watch"]({}).pipe(Stream.take(1), Stream.runCollect));
    expect(snapshot?._tag === "Snapshot" ? snapshot.clips.map((clip) => clip.id) : null).toEqual([clipId("mac-old-keep")]);
    expect(existsSync(join(target.dataDir, "clips", "mac-old-keep.png"))).toBe(true);
    expect(existsSync(join(target.dataDir, "clips", "mac-old-drop.png"))).toBe(false);
  });

  test("reading clips needs the clipboard scope", async () => {
    const target = await started();
    const { token } = await pairDevice(target);
    const error = await withClient(target, token, (client) => Effect.flip(client["clips.read"]({ id: clipId("mac-text-0001"), offset: 0 })));
    expect(error).toMatchObject({ _tag: "AuthError", requiredScope: "clipboard" });
  });

  test("turning history off hides Mac clips but keeps what phones sent", async () => {
    const target = await started();
    const { token } = await clipboardPhone(target);
    await historyOn(target);
    target.app.emit({ t: "clip", clip: macClip("mac-secret-01", { text: "hunter2" }) });
    await Bun.sleep(50);
    const sent = await withClient(target, token, (client) =>
      client["clips.send.begin"]({ kind: "link", name: null, mime: null, bytes: 0, sha256: null, text: "https://example.com" }),
    );
    target.app.emit({ t: "clipPolicy", policy: { enabled: false, keepDays: 7 } });
    await Bun.sleep(50);
    const { snapshot, error } = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const [snapshot] = yield* client["clips.watch"]({}).pipe(Stream.take(1), Stream.runCollect);
        const error = yield* Effect.flip(client["clips.read"]({ id: clipId("mac-secret-01"), offset: 0 }));
        return { snapshot, error };
      }),
    );
    expect(snapshot).toMatchObject({ _tag: "Snapshot", enabled: false });
    expect(snapshot?._tag === "Snapshot" ? snapshot.clips.map((clip) => clip.id) : null).toEqual(sent.clip === null ? [] : [sent.clip.id]);
    expect(error).toMatchObject({ _tag: "Unavailable", message: "Clipboard history is off on the Mac" });
  });

  test("a pushed clip reaches phones with history off and still ages out", async () => {
    const target = await started();
    const { token } = await clipboardPhone(target);
    target.app.emit({ t: "clipPolicy", policy: { enabled: false, keepDays: 1 } });
    target.app.emit({ t: "clip", clip: macClip("mac-quiet-001", { text: "not for phones" }) });
    target.app.emit({ t: "clip", clip: macClip("mac-pushed-01", { text: "for the phone", pushed: true }) });
    target.app.emit({ t: "clip", clip: macClip("mac-pushed-02", { text: "stale push", pushed: true, at: Date.now() - 2 * DAY }) });
    await Bun.sleep(100);
    const { snapshot, chunk } = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const [snapshot] = yield* client["clips.watch"]({}).pipe(Stream.take(1), Stream.runCollect);
        const chunk = yield* client["clips.read"]({ id: clipId("mac-pushed-01"), offset: 0 });
        return { snapshot, chunk };
      }),
    );
    expect(snapshot?._tag === "Snapshot" ? snapshot.clips.map((clip) => clip.id) : null).toEqual([clipId("mac-pushed-01")]);
    expect(Buffer.from(chunk.data, "base64").toString()).toBe("for the phone");
  });

  test("two readers of a copied file share one materialization", async () => {
    const target = await started();
    const { token } = await clipboardPhone(target);
    await historyOn(target);
    let asked = 0;
    target.app.answer = (q) => {
      if (q._tag !== "ClipMaterialize") return null;
      asked += 1;
      return Bun.sleep(200).then(() => {
        writeFileSync(join(target.dataDir, "clips", `${q.id}.txt`), "file body");
        return { _tag: "ClipMaterialize", stored: `${q.id}.txt`, bytes: 9, files: null };
      });
    };
    target.app.emit({ t: "clip", clip: macClip("mac-file-0001", { kind: "file", text: null, name: "notes.txt", bytes: 9, origin: "/Users/me/notes.txt" }) });
    await Bun.sleep(50);
    const read = () => withClient(target, token, (client) => client["clips.read"]({ id: clipId("mac-file-0001"), offset: 0 }));
    const chunks = await Promise.all([read(), read()]);
    expect(asked).toBe(1);
    expect(chunks.map((chunk) => Buffer.from(chunk.data, "base64").toString())).toEqual(["file body", "file body"]);
  });
});
