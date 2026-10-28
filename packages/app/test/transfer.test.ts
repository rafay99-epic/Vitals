import { describe, expect, test } from "bun:test";
import { CLIP_LIMITS, Clip, type ClipChunk, ClipId, type ClipSendBegin, UploadId } from "@vitals/contracts";
import * as Schema from "effect/Schema";

import { fromBase64, toBase64 } from "../src/lib/base64.ts";
import { type ByteSink, byteLength, chunkOffsets, type ClipLink, downloadClip, fraction, type Reply, Transfer, uploadAll } from "../src/state/transfer.ts";

const CHUNK = CLIP_LIMITS.chunkBytes;
const id = Schema.decodeUnknownSync(ClipId)("clip-0001");
const uploadId = Schema.decodeUnknownSync(UploadId)("upload-0001");

const stored = (kind: Clip["kind"]): Clip =>
  Schema.decodeUnknownSync(Clip)({ id: "clip-0002", kind, at: 1, deviceId: "phone-1", source: null, text: null, truncated: false, name: null, mime: null, bytes: 0, files: null, thumb: null, pinned: false });

const bytesOf = (size: number): Uint8Array => Uint8Array.from({ length: size }, (_, index) => index % 251);

const ok = <A>(value: A): Reply<A> => ({ ok: true, value });
const dropped: Reply<never> = { ok: false, error: { _tag: "NotConnected", message: "Not connected to your Mac" } };

/** A Mac in memory. `drop` decides which calls fail as if the connection went away. */
const fakeMac = (file: Uint8Array, drop: (call: number) => boolean = () => false) => {
  let calls = 0;
  let inFlight = 0;
  let peak = 0;
  const received = new Map<number, string>();
  const tick = async <A>(answer: () => A): Promise<Reply<A>> => {
    calls += 1;
    const call = calls;
    inFlight += 1;
    peak = Math.max(peak, inFlight);
    await Bun.sleep(1);
    inFlight -= 1;
    return drop(call) ? dropped : ok(answer());
  };
  const link: ClipLink = {
    read: ({ offset }) =>
      tick((): ClipChunk => {
        const end = Math.min(file.length, offset + CHUNK);
        return { data: toBase64(file.subarray(offset, end)), offset, total: file.length, done: end >= file.length };
      }),
    begin: (input: ClipSendBegin) => tick(() => ({ uploadId, clip: input.bytes === 0 ? stored("text") : null })),
    chunk: ({ offset, data }) =>
      tick(() => {
        received.set(offset, data);
        return { received: offset + byteLength(data) };
      }),
    finish: () => tick(() => stored("file")),
    whenOnline: (ready) => {
      ready();
      return () => {};
    },
  };
  return { link, received, peak: () => peak, calls: () => calls };
};

const memorySink = () => {
  const parts = new Map<number, Uint8Array>();
  let finished = false;
  let aborted = false;
  const sink: ByteSink = {
    write: async (offset, base64) => {
      parts.set(offset, fromBase64(base64));
    },
    finish: async () => {
      finished = true;
    },
    abort: () => {
      aborted = true;
    },
  };
  const joined = (): Uint8Array => {
    const ordered = [...parts.entries()].sort(([left], [right]) => left - right).map(([, part]) => part);
    const out = new Uint8Array(ordered.reduce((sum, part) => sum + part.length, 0));
    let at = 0;
    for (const part of ordered) {
      out.set(part, at);
      at += part.length;
    }
    return out;
  };
  return { sink, joined, finished: () => finished, aborted: () => aborted };
};

const fast = { pauseMs: 0 } as const;

describe("chunk math", () => {
  test("offsets cover the item in chunk-sized steps", () => {
    expect(chunkOffsets(0)).toEqual([]);
    expect(chunkOffsets(1)).toEqual([0]);
    expect(chunkOffsets(CHUNK)).toEqual([0]);
    expect(chunkOffsets(CHUNK * 2 + 1)).toEqual([0, CHUNK, CHUNK * 2]);
  });

  test("base64 length gives back the raw size", () => {
    for (const size of [0, 1, 2, 3, 4, 5, 1000]) expect(byteLength(toBase64(bytesOf(size)))).toBe(size);
  });

  test("progress is a fraction of the total, and empty items count once done", () => {
    expect(fraction({ done: 3, total: 4, phase: "running", error: null })).toBe(0.75);
    expect(fraction({ done: 0, total: 0, phase: "running", error: null })).toBe(0);
    expect(fraction({ done: 0, total: 0, phase: "done", error: null })).toBe(1);
  });
});

describe("downloadClip", () => {
  test("gets every chunk, never more than four at once, and reports exact progress", async () => {
    const file = bytesOf(CHUNK * 9 + 123);
    const mac = fakeMac(file);
    const out = memorySink();
    const transfer = new Transfer("file", 0, mac.link, fast);
    const seen: Array<number> = [];
    transfer.progress.subscribe(() => seen.push(transfer.progress.get().done));
    expect(await downloadClip(transfer, mac.link, id, out.sink)).toBe(true);
    expect(out.joined()).toEqual(file);
    expect(out.finished()).toBe(true);
    expect(mac.peak()).toBeLessThanOrEqual(4);
    expect(mac.peak()).toBeGreaterThan(1);
    expect(transfer.progress.get()).toEqual({ done: file.length, total: file.length, phase: "done", error: null });
    expect(seen.every((done, index) => index === 0 || done >= (seen[index - 1] ?? 0))).toBe(true);
  });

  test("a dropped call waits for the Mac and retries the same chunk", async () => {
    const file = bytesOf(CHUNK * 5);
    const mac = fakeMac(file, (call) => call === 3 || call === 4);
    const out = memorySink();
    const transfer = new Transfer("file", file.length, mac.link, fast);
    expect(await downloadClip(transfer, mac.link, id, out.sink)).toBe(true);
    expect(out.joined()).toEqual(file);
    expect(transfer.progress.get().done).toBe(file.length);
    expect(mac.calls()).toBe(5 + 2);
  });

  test("cancel stops the download and aborts the sink", async () => {
    const file = bytesOf(CHUNK * 20);
    const mac = fakeMac(file);
    const out = memorySink();
    const transfer = new Transfer("file", file.length, mac.link, fast);
    const running = downloadClip(transfer, mac.link, id, out.sink);
    setTimeout(() => transfer.cancel(), 3);
    expect(await running).toBe(false);
    expect(transfer.progress.get().phase).toBe("cancelled");
    expect(out.aborted()).toBe(true);
    expect(out.finished()).toBe(false);
    expect(mac.calls()).toBeLessThan(20);
  });

  test("an error from the Mac fails the transfer with its message", async () => {
    const mac = fakeMac(bytesOf(CHUNK * 3));
    const link: ClipLink = { ...mac.link, read: async () => ({ ok: false, error: { _tag: "Unavailable", message: "The Mac could not read that file" } }) };
    const out = memorySink();
    const transfer = new Transfer("file", 0, link, fast);
    expect(await downloadClip(transfer, link, id, out.sink)).toBe(false);
    expect(transfer.progress.get()).toMatchObject({ phase: "failed", error: "The Mac could not read that file" });
    expect(out.aborted()).toBe(true);
  });
});

describe("uploadAll", () => {
  const sourceOf = (file: Uint8Array) => ({ size: file.length, read: async (offset: number, length: number) => toBase64(file.subarray(offset, offset + length)) });

  test("sends every chunk at chunk-aligned offsets and resumes after a dropped call", async () => {
    const file = bytesOf(CHUNK * 6 + 7);
    const mac = fakeMac(file, (call) => call === 4);
    const transfer = new Transfer("photo", file.length, mac.link, fast);
    const clips = await uploadAll(transfer, mac.link, [{ kind: "file", name: "a.bin", mime: null, sha256: null, source: sourceOf(file) }]);
    expect(clips?.map((clip) => clip.kind)).toEqual(["file"]);
    expect([...mac.received.keys()].sort((left, right) => left - right)).toEqual([...chunkOffsets(file.length)]);
    expect([...mac.received.keys()].every((offset) => offset % CHUNK === 0)).toBe(true);
    expect(mac.peak()).toBeLessThanOrEqual(4);
    expect(transfer.progress.get()).toEqual({ done: file.length, total: file.length, phase: "done", error: null });
  });

  test("text comes back complete from begin, with no chunks", async () => {
    const mac = fakeMac(new Uint8Array());
    const transfer = new Transfer("text", 0, mac.link, fast);
    const clips = await uploadAll(transfer, mac.link, [{ kind: "text", text: "hello" }]);
    expect(clips?.length).toBe(1);
    expect(mac.calls()).toBe(1);
    expect(fraction(transfer.progress.get())).toBe(1);
  });

  test("cancel resolves null and closes the source", async () => {
    const file = bytesOf(CHUNK * 20);
    const mac = fakeMac(file);
    let closed = false;
    const transfer = new Transfer("file", file.length, mac.link, fast);
    const running = uploadAll(transfer, mac.link, [{ kind: "file", name: "a.bin", mime: null, sha256: null, source: { ...sourceOf(file), close: () => (closed = true) } }]);
    setTimeout(() => transfer.cancel(), 3);
    expect(await running).toBeNull();
    expect(closed).toBe(true);
    expect(mac.received.size).toBeLessThan(20);
  });
});
