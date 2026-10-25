import { Database } from "bun:sqlite";
import { afterEach, describe, expect, test } from "bun:test";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { connect } from "node:tls";

import { type Drop, type DropFileOffer, type ToApp, DROP_LIMITS, DeviceId, DropFileId, DropId } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { spkiPin } from "../src/drop/tls.ts";
import { type FakeApp, type Gateway, pairDevice, startGateway, withClient } from "./harness.ts";

const PART = DROP_LIMITS.partBytes;
const deviceIdOf = Schema.decodeUnknownSync(DeviceId);
const dropIdOf = Schema.decodeUnknownSync(DropId);
const firstFile = Schema.decodeUnknownSync(DropFileId)("0");

let gateway: Gateway | null = null;

afterEach(async () => {
  await gateway?.stop();
  gateway = null;
});

const started = async () => {
  gateway = await startGateway();
  return gateway;
};

const sha256 = (bytes: Uint8Array) => new Bun.CryptoHasher("sha256").update(bytes).digest("hex");

const offered = (name: string, bytes: Uint8Array, sha: string | null = sha256(bytes)): DropFileOffer => ({
  name,
  path: null,
  size: bytes.length,
  mime: "application/octet-stream",
  sha256: sha,
});

const fileUrl = (base: string, drop: Drop, fileId = "0") => `${base}/api/drop/${drop.id}/${fileId}`;

const put = (url: string, ticket: string, body: Uint8Array, start: number, size: number, length = body.length) =>
  fetch(url, {
    method: "PUT",
    headers: { authorization: `Drop ${ticket}`, "content-range": `bytes ${String(start)}-${String(start + length - 1)}/${String(size)}` },
    body,
  });

const waitFor = async <A>(find: () => A | undefined, what: string): Promise<A> => {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    const found = find();
    if (found !== undefined) return found;
    await Bun.sleep(10);
  }
  throw new Error(`timed out waiting for ${what}`);
};

const toMac = <T extends ToApp["t"]>(app: FakeApp, t: T, match: (message: Extract<ToApp, { t: T }>) => boolean = () => true) =>
  waitFor(
    () => app.received.find((message): message is Extract<ToApp, { t: T }> => message.t === t && match(message as Extract<ToApp, { t: T }>)),
    t,
  );

const macDrop = (app: FakeApp, id: string, state: Drop["state"]) =>
  toMac(app, "drop", (message) => message.drop.id === id && message.drop.state === state);

describe("drop: phone to Mac", () => {
  test("parts land out of order, a cut part resumes after HEAD, and the Mac is told", async () => {
    const target = await started();
    const { token, deviceId } = await pairDevice(target);
    const bytes = new Uint8Array(randomBytes(PART * 2 + 1_000));
    const { drop, ticket } = await withClient(target, token, (client) => client["drop.offer"]({ files: [offered("video.mov", bytes)] }));
    expect(drop.state).toBe("running");
    const url = fileUrl(target.base, drop);

    expect((await put(url, ticket.ticket, bytes.subarray(PART * 2), PART * 2, bytes.length)).status).toBe(204);
    expect((await put(url, ticket.ticket, bytes.subarray(0, PART), 0, bytes.length)).status).toBe(204);
    const cut = await put(url, ticket.ticket, bytes.subarray(PART, PART + 1_000), PART, bytes.length, PART);
    expect(cut.status).toBe(400);

    const resume = await fetch(url, { method: "HEAD", headers: { authorization: `Drop ${ticket.ticket}` } });
    expect(resume.status).toBe(200);
    expect(resume.headers.get("x-vitals-parts")).toBe("0,2");
    expect(resume.headers.get("content-length")).toBe(String(bytes.length));

    const last = await put(url, ticket.ticket, bytes.subarray(PART, PART * 2), PART, bytes.length);
    expect(last.status).toBe(204);
    expect(last.headers.get("x-vitals-done")).toBe(String(bytes.length));

    const delivered = await toMac(target.app, "dropReceived", (message) => message.id === drop.id);
    expect(delivered).toMatchObject({ from: { _tag: "Device", deviceId }, files: [{ stored: `${drop.id}/0`, name: "video.mov", size: bytes.length }] });
    expect(Buffer.compare(readFileSync(join(target.dataDir, "drop", `${drop.id}/0`)), bytes)).toBe(0);
    await macDrop(target.app, drop.id, "done");
  });

  test("a file whose sha256 doesn't match is refused and starts over", async () => {
    const target = await started();
    const { token } = await pairDevice(target);
    const bytes = new Uint8Array(randomBytes(4_096));
    const { drop, ticket } = await withClient(target, token, (client) => client["drop.offer"]({ files: [offered("a.bin", bytes, "0".repeat(64))] }));
    const url = fileUrl(target.base, drop);
    const response = await put(url, ticket.ticket, bytes, 0, bytes.length);
    expect(response.status).toBe(422);
    const after = await fetch(url, { method: "HEAD", headers: { authorization: `Drop ${ticket.ticket}` } });
    expect(after.headers.get("x-vitals-parts")).toBe("");
  });

  test("tickets only open their own drop, for their own device, until they expire", async () => {
    const target = await started();
    const first = await pairDevice(target);
    const second = await pairDevice(target);
    const bytes = new Uint8Array(randomBytes(64));
    const mine = await withClient(target, first.token, (client) => client["drop.offer"]({ files: [offered("a.bin", bytes)] }));
    const theirs = await withClient(target, second.token, (client) => client["drop.offer"]({ files: [offered("b.bin", bytes)] }));

    expect((await put(fileUrl(target.base, theirs.drop), mine.ticket.ticket, bytes, 0, 64)).status).toBe(401);
    expect((await put(fileUrl(target.base, mine.drop), "x".repeat(43), bytes, 0, 64)).status).toBe(401);
    const stranger = await withClient(target, second.token, (client) => Effect.flip(client["drop.cancel"]({ id: mine.drop.id })));
    expect(stranger).toMatchObject({ _tag: "Unavailable" });

    const db = new Database(join(target.dataDir, "remote.db"));
    db.run("UPDATE drop_tickets SET expires_at = 1");
    db.close();
    const expired = await put(fileUrl(target.base, mine.drop), mine.ticket.ticket, bytes, 0, 64);
    expect(expired.status).toBe(401);
    expect(await expired.json()).toMatchObject({ code: "expired" });
  });

  test("bytes wait for the Mac to accept, need whole parts, and stop while paused", async () => {
    const target = await started();
    const { token } = await pairDevice(target);
    target.app.emit({ t: "dropPolicy", policy: { autoAccept: false, askWeb: true, maxBytes: 1024 ** 3 } });
    await Bun.sleep(50);
    const bytes = new Uint8Array(randomBytes(PART + 10));
    const { drop, ticket } = await withClient(target, token, (client) => client["drop.offer"]({ files: [offered("b.bin", bytes)] }));
    expect(drop.state).toBe("asking");
    await macDrop(target.app, drop.id, "asking");
    const url = fileUrl(target.base, drop);
    expect((await put(url, ticket.ticket, bytes.subarray(0, PART), 0, bytes.length)).status).toBe(409);

    target.app.emit({ t: "dropDecision", id: drop.id, accept: true });
    await macDrop(target.app, drop.id, "running");
    expect((await put(url, ticket.ticket, bytes.subarray(1, PART + 1), 1, bytes.length)).status).toBe(416);
    expect((await put(url, ticket.ticket, bytes.subarray(PART), PART, bytes.length + 1)).status).toBe(416);

    target.app.emit({ t: "dropPause", id: drop.id, paused: true });
    await macDrop(target.app, drop.id, "paused");
    expect((await put(url, ticket.ticket, bytes.subarray(0, PART), 0, bytes.length)).status).toBe(423);
  });

  test("an offer bigger than the free space is refused in plain words", async () => {
    const target = await started();
    const { token } = await pairDevice(target);
    const error = await withClient(target, token, (client) =>
      Effect.flip(client["drop.offer"]({ files: [{ name: "huge.bin", path: null, size: 2 ** 52, mime: null, sha256: null }] })),
    );
    expect(error).toMatchObject({ _tag: "CommandRejected" });
    expect(error.message).toMatch(/^Your Mac needs [\d.]+ TB free for this$/);
  });

  test("cancelling removes the staged bytes and refuses more", async () => {
    const target = await started();
    const { token } = await pairDevice(target);
    const bytes = new Uint8Array(randomBytes(PART + 10));
    const { drop, ticket } = await withClient(target, token, (client) => client["drop.offer"]({ files: [offered("c.bin", bytes)] }));
    const url = fileUrl(target.base, drop);
    expect((await put(url, ticket.ticket, bytes.subarray(0, PART), 0, bytes.length)).status).toBe(204);
    expect(existsSync(join(target.dataDir, "drop", drop.id))).toBe(true);
    const cancelled = await withClient(target, token, (client) => client["drop.cancel"]({ id: drop.id }));
    expect(cancelled.state).toBe("cancelled");
    await macDrop(target.app, drop.id, "cancelled");
    await waitFor(() => (existsSync(join(target.dataDir, "drop", drop.id)) ? undefined : true), "staging removed");
    expect((await put(url, ticket.ticket, bytes.subarray(PART), PART, bytes.length)).status).toBe(410);
  });
});

describe("drop: Mac to phone", () => {
  test("waits for an offline phone, asks when it connects, then serves exact ranges", async () => {
    const target = await started();
    const { token, deviceId } = await pairDevice(target);
    const folder = mkdtempSync(join(tmpdir(), "vitals-origin-"));
    const bytes = new Uint8Array(randomBytes(3 * 1024 * 1024 + 7));
    const origin = join(folder, "photo.heic");
    writeFileSync(origin, bytes);

    target.app.emit({ t: "dropSend", to: [deviceIdOf(deviceId)], files: [{ name: "photo.heic", path: null, size: bytes.length, mime: "image/heic", origin }] });
    const waiting = await toMac(target.app, "drop", (message) => message.drop.state === "waiting");
    const id = waiting.drop.id;
    expect(waiting.drop).toMatchObject({ from: { _tag: "Mac", name: "Test Mac" }, to: { _tag: "Device", deviceId }, bytes: bytes.length });

    const result = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        yield* client["drop.watch"]({}).pipe(
          Stream.flatMap((event) => Stream.fromIterable(event._tag === "Snapshot" ? event.drops : event._tag === "Changed" ? [event.drop] : [])),
          Stream.filter((drop) => drop.id === id && drop.state === "asking"),
          Stream.take(1),
          Stream.runDrain,
        );
        const { ticket } = yield* client["drop.accept"]({ id: dropIdOf(id) });
        const url = `${target.base}/api/drop/${id}/0`;
        const headers = { authorization: `Drop ${ticket.ticket}` };
        const slice = yield* Effect.promise(() => fetch(url, { headers: { ...headers, range: "bytes=100-199" } }));
        const sliceBytes = new Uint8Array(yield* Effect.promise(() => slice.arrayBuffer()));
        const tail = yield* Effect.promise(() => fetch(url, { headers: { ...headers, range: `bytes=${String(bytes.length - 5)}-` } }));
        const tailBytes = new Uint8Array(yield* Effect.promise(() => tail.arrayBuffer()));
        const whole = yield* Effect.promise(() => fetch(url, { headers: { ...headers, range: "bytes=0-" } }));
        const wholeBytes = new Uint8Array(yield* Effect.promise(() => whole.arrayBuffer()));
        yield* Effect.promise(() => toMac(target.app, "drop", (message) => message.drop.id === id && message.drop.state === "running" && message.drop.done === bytes.length));
        const outside = yield* Effect.promise(() => fetch(url, { headers: { ...headers, range: `bytes=${String(bytes.length)}-` } }));
        const wrong = yield* Effect.flip(client["drop.received"]({ id: dropIdOf(id), fileId: firstFile, sha256: "f".repeat(64) }));
        const done = yield* client["drop.received"]({ id: dropIdOf(id), fileId: firstFile, sha256: sha256(bytes) });
        return { slice, sliceBytes, tail, tailBytes, whole, wholeBytes, outside, wrong, done };
      }),
    );

    expect(result.slice.status).toBe(206);
    expect(result.slice.headers.get("content-range")).toBe(`bytes 100-199/${String(bytes.length)}`);
    expect(Buffer.compare(result.sliceBytes, bytes.subarray(100, 200))).toBe(0);
    expect(Buffer.compare(result.tailBytes, bytes.subarray(bytes.length - 5))).toBe(0);
    expect(result.whole.status).toBe(206);
    expect(result.whole.headers.get("content-type")).toBe("image/heic");
    expect(result.whole.headers.get("content-length")).toBe(String(bytes.length));
    expect(Buffer.compare(result.wholeBytes, bytes)).toBe(0);
    expect(result.outside.status).toBe(416);
    expect(result.wrong).toMatchObject({ _tag: "CommandRejected" });
    expect(result.done.state).toBe("done");
    expect(result.done.files[0]?.sha256).toBe(sha256(bytes));
  });
});

describe("drop: Wi-Fi TLS", () => {
  test("the certificate matches the advertised pin and carries a drop", async () => {
    const target = await started();
    const { token } = await pairDevice(target);
    const bytes = new Uint8Array(randomBytes(1_000));
    const { hello, offer } = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const hello = yield* client["server.hello"]({});
        const offer = yield* client["drop.offer"]({ files: [offered("tls.bin", bytes)] });
        return { hello, offer };
      }),
    );
    expect(hello.drop).toBe(true);
    const tls = hello.routes?.tls;
    expect(tls?.port).toBe(Number(new URL(target.tlsBase).port));

    const peer = await new Promise<Buffer>((resolve, reject) => {
      const socket = connect({ host: "127.0.0.1", port: tls?.port ?? 0, rejectUnauthorized: false }, () => {
        resolve(socket.getPeerCertificate(true).raw);
        socket.end();
      });
      socket.on("error", reject);
    });
    expect(spkiPin(peer)).toBe(tls?.pin ?? "");

    const health = await fetch(`${target.tlsBase}/api/health`, { tls: { rejectUnauthorized: false } });
    expect(health.status).toBe(200);
    const response = await fetch(fileUrl(target.tlsBase, offer.drop), {
      method: "PUT",
      headers: { authorization: `Drop ${offer.ticket.ticket}`, "content-range": `bytes 0-999/1000` },
      body: bytes,
      tls: { rejectUnauthorized: false },
    });
    expect(response.status).toBe(204);
    const done = await macDrop(target.app, offer.drop.id, "done");
    expect(done.drop.route).toBe("lan");
  });
});
