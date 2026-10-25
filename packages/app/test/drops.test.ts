import { describe, expect, test } from "bun:test";
import { type Connection, type ConnectionState, NotConnected, Store, type VitalsClient } from "@vitals/client-runtime";
import { DeviceId, Drop, type DropFile, Hello, PROTOCOL_VERSION } from "@vitals/contracts";
import type { DownloadJob, TransferEvent, UploadJob } from "@vitals/tailnet/drop";
import * as Schema from "effect/Schema";

import { type DropEngine, dropEndpoints, dropLabel, folderOf, MacDrops, nextJobs, REFRESH_EARLY_MS, refreshDelay, type Shelf, shouldAccept, ticketUsable } from "../src/state/drops.ts";

const me = Schema.decodeUnknownSync(DeviceId)("phone-1");
const decodeDrop = Schema.decodeUnknownSync(Drop);
const HOUR = 3_600_000;

const file = (id: string, size: number, extra: Partial<Record<keyof DropFile, unknown>> = {}) => ({ id, name: `${id}.mov`, path: null, size, mime: "video/quicktime", sha256: null, done: 0, ...extra });

const drop = (state: Drop["state"], files: ReadonlyArray<ReturnType<typeof file>>, direction: "in" | "out" = "in"): Drop => {
  const mac = { _tag: "Mac", name: "MacBook Pro" };
  const phone = { _tag: "Device", deviceId: me, name: "Pixel" };
  return decodeDrop({
    id: "drop-0001",
    from: direction === "in" ? mac : phone,
    to: direction === "in" ? phone : mac,
    files,
    bytes: files.reduce((sum, item) => sum + item.size, 0),
    done: 0,
    state,
    route: null,
    createdAt: 1,
    updatedAt: 1,
    error: null,
  });
};

interface Call {
  readonly method: string;
  readonly payload: unknown;
}

const client = new Proxy({}, { get: (_, method) => (payload: unknown): Call => ({ method: String(method), payload }) });

const fake = (respond: (call: Call) => unknown) => {
  const calls: Array<Call> = [];
  const connection: Connection = {
    state: new Store<ConnectionState>({ _tag: "Idle" }),
    call: async <A, E>(run: (client: VitalsClient) => unknown) => {
      const call = run(client as VitalsClient) as Call;
      calls.push(call);
      return { ok: true, value: respond(call) } as { readonly ok: true; readonly value: A } | { readonly ok: false; readonly error: E };
    },
    watch: () => () => {},
    wake: () => {},
    suspend: () => {},
    dispose: () => {},
  };
  return { connection, calls };
};

const engine = () => {
  const started: Array<DownloadJob | UploadJob> = [];
  const listeners = new Set<(event: TransferEvent) => void>();
  const value: DropEngine = {
    supported: true,
    upload: async (job) => void started.push(job),
    download: async (job) => void started.push(job),
    cancel: async () => {},
    listen: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
  return { value, started, emit: (event: TransferEvent) => listeners.forEach((listener) => listener(event)) };
};

const shelf = (): Shelf => {
  const kept = new Map<string, string>();
  return { read: async (key) => kept.get(key) ?? null, write: (key, body) => void kept.set(key, body) };
};

const ticket = { ticket: "t".repeat(40), expiresAt: Date.now() + HOUR };

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

const readyHello = Schema.decodeUnknownSync(Hello)({
  protocol: PROTOCOL_VERSION,
  mac: null,
  keepAwake: null,
  lastEventSeq: 0,
  alerts: [],
  serverTime: 1,
  scopes: ["read", "operate", "files"],
  drop: true,
});

describe("drop endpoints", () => {
  test("Wi-Fi hosts first with the pin, then built-in Tailscale, then Tailscale", () => {
    const tls = { port: 47822, pin: `${"A".repeat(43)}=` };
    expect(dropEndpoints({ hosts: ["192.168.1.4", "192.168.1.4", "fe80::1"], tls, tailnet: "https://mac.tail.ts.net/", builtIn: true })).toEqual([
      { url: "https://192.168.1.4:47822", pin: tls.pin, tsnet: false },
      { url: "https://[fe80::1]:47822", pin: tls.pin, tsnet: false },
      { url: "https://mac.tail.ts.net", pin: null, tsnet: true },
      { url: "https://mac.tail.ts.net", pin: null, tsnet: false },
    ]);
  });

  test("no pin means no Wi-Fi route, and built-in Tailscale off skips tsnet", () => {
    expect(dropEndpoints({ hosts: ["10.0.0.2"], tls: undefined, tailnet: "https://mac.ts.net", builtIn: false })).toEqual([{ url: "https://mac.ts.net", pin: null, tsnet: false }]);
  });
});

describe("drop queue rules", () => {
  test("two files at a time", () => {
    const jobs = [{ state: "running" as const }, { state: "queued" as const }, { state: "queued" as const }];
    expect(nextJobs(jobs)).toHaveLength(1);
    expect(nextJobs([{ state: "done" as const }, { state: "queued" as const }, { state: "queued" as const }, { state: "queued" as const }])).toHaveLength(2);
    expect(nextJobs([{ state: "starting" as const }, { state: "running" as const }, { state: "queued" as const }])).toHaveLength(0);
  });

  test("tickets refresh five minutes before they expire", () => {
    expect(refreshDelay(10 * 60_000, 0)).toBe(5 * 60_000);
    expect(refreshDelay(60_000, 0)).toBe(0);
    expect(ticketUsable({ ticket: "x", expiresAt: REFRESH_EARLY_MS + 1 }, 0)).toBe(true);
    expect(ticketUsable({ ticket: "x", expiresAt: REFRESH_EARLY_MS }, 0)).toBe(false);
  });

  test("auto-accept only Mac drops to this device that are asking", () => {
    expect(shouldAccept(drop("asking", [file("a", 1)]), me, true)).toBe(true);
    expect(shouldAccept(drop("asking", [file("a", 1)]), me, false)).toBe(false);
    expect(shouldAccept(drop("running", [file("a", 1)]), me, true)).toBe(false);
    expect(shouldAccept(drop("asking", [file("a", 1)], "out"), me, true)).toBe(false);
  });

  test("the engine gets the folder part of a file's path", () => {
    expect(folderOf("Trip/day 2/b.mov")).toBe("Trip/day 2");
    expect(folderOf("b.mov")).toBeNull();
    expect(folderOf(null)).toBeNull();
  });

  test("labels name one file, a shared folder, or a count", () => {
    expect(dropLabel(drop("running", [file("trip", 1)]))).toBe("trip.mov");
    expect(dropLabel(drop("running", [file("a", 1, { path: "Trip/a.mov" }), file("b", 1, { path: "Trip/day 2/b.mov" })]))).toBe("Trip");
    expect(dropLabel(drop("running", [file("a", 1), file("b", 1), file("c", 1)]))).toBe("3 files");
  });
});

describe("MacDrops", () => {
  test("accepts on its own, downloads two at a time, and confirms each file with its hash", async () => {
    const asking = drop("asking", [file("a", 10), file("b", 20), file("c", 30)]);
    const running = { ...asking, state: "running" as const };
    const { connection, calls } = fake((call) => (call.method === "drop.accept" ? { drop: running, ticket } : running));
    const transfers = engine();
    const drops = new MacDrops(connection, transfers.value, shelf(), me, () => [], () => {});
    await drops.ready;
    const finished: Array<string> = [];
    drops.onFinish((finish) => finished.push(finish._tag));
    drops.apply({ _tag: "Snapshot", drops: [asking] });
    await settle();
    expect(calls.map((call) => call.method)).toEqual(["drop.accept"]);
    await settle();
    expect(transfers.started.map((job) => job.fileId)).toEqual(["a", "b"]);
    expect(transfers.started[0]?.title).toBe("Getting a.mov from your Mac");
    transfers.emit({ type: "done", job: transfers.started[0]?.job ?? "", sha256: "f".repeat(64), uri: "file:///a.mov" });
    await settle();
    expect(transfers.started.map((job) => job.fileId)).toEqual(["a", "b", "c"]);
    expect(calls.at(-1)).toEqual({ method: "drop.received", payload: { id: asking.id, fileId: "a", sha256: "f".repeat(64) } });
    expect(drops.received.get().map((saved) => saved.name)).toEqual(["a.mov"]);
    drops.apply({ _tag: "Changed", drop: { ...running, state: "done" } });
    expect(finished).toEqual(["Received"]);
    drops.dispose();
  });

  test("asks first when Start without asking is off", async () => {
    const { connection, calls } = fake(() => null);
    const drops = new MacDrops(connection, engine().value, shelf(), me, () => [], () => {});
    await drops.ready;
    drops.setAutoAccept(false);
    drops.apply({ _tag: "Snapshot", drops: [drop("asking", [file("a", 10)])] });
    await settle();
    expect(calls).toEqual([]);
    drops.dispose();
  });

  test("a non-retryable error re-issues the job with a fresh ticket, a retryable one waits for the engine", async () => {
    const running = drop("running", [file("a", 10)]);
    const { connection, calls } = fake((call) => (call.method === "drop.ticket" ? ticket : running));
    const transfers = engine();
    const drops = new MacDrops(connection, transfers.value, shelf(), me, () => [], () => {});
    await drops.ready;
    drops.apply({ _tag: "Snapshot", drops: [running] });
    await settle();
    expect(transfers.started).toHaveLength(1);
    const job = transfers.started[0]?.job ?? "";
    transfers.emit({ type: "error", job, message: "Wi-Fi dropped", retryable: true });
    await settle();
    expect(transfers.started).toHaveLength(1);
    expect(drops.live.get().get(running.id)?.stalled).toBe(true);
    transfers.emit({ type: "error", job, message: "Ticket expired", retryable: false });
    await settle();
    expect(transfers.started).toHaveLength(2);
    expect(calls.filter((call) => call.method === "drop.ticket")).toHaveLength(2);
    drops.dispose();
  });

  test("a retry while the phone is offline waits for the connection instead of failing", async () => {
    const running = drop("running", [file("a", 10)]);
    const { connection, calls } = fake((call) => (call.method === "drop.ticket" ? ticket : running));
    const online = connection.call;
    const offline: Connection["call"] = async () => ({ ok: false, error: new NotConnected({ message: "offline" }) });
    const transfers = engine();
    const reports: Array<string> = [];
    const drops = new MacDrops(connection, transfers.value, shelf(), me, () => [], (message) => reports.push(message));
    await drops.ready;
    drops.apply({ _tag: "Snapshot", drops: [running] });
    await settle();
    const job = transfers.started[0]?.job ?? "";
    Object.assign(connection, { call: offline });
    connection.state.set({ _tag: "Backoff", attempt: 1, retryAt: Date.now() + 1_000, reason: "Can't reach your Mac", failures: [] });
    transfers.emit({ type: "error", job, message: "The Mac no longer has this transfer", retryable: false });
    await settle();
    expect(transfers.started).toHaveLength(1);
    expect(reports).toEqual([]);
    Object.assign(connection, { call: online });
    connection.state.set({ _tag: "Ready", hello: readyHello, since: Date.now(), route: "lan", latencyMs: 5 });
    await settle();
    expect(transfers.started).toHaveLength(2);
    expect(calls.filter((call) => call.method === "drop.ticket").length).toBeGreaterThan(0);
    drops.dispose();
  });

  test("a transfer that keeps failing says Stopped, and Try again starts it over", async () => {
    const running = drop("running", [file("a", 10)]);
    const { connection } = fake((call) => (call.method === "drop.ticket" ? ticket : running));
    const transfers = engine();
    const reports: Array<string> = [];
    const drops = new MacDrops(connection, transfers.value, shelf(), me, () => [], (message) => reports.push(message));
    await drops.ready;
    drops.apply({ _tag: "Snapshot", drops: [running] });
    await settle();
    for (let attempt = 0; attempt < 3; attempt += 1) {
      transfers.emit({ type: "error", job: transfers.started.at(-1)?.job ?? "", message: "The Mac refused part of the file", retryable: false });
      await settle();
    }
    expect(drops.live.get().get(running.id)?.failed).toBe(true);
    expect(reports).toEqual(["The Mac refused part of the file"]);
    const before = transfers.started.length;
    drops.retry(running.id);
    await settle();
    expect(transfers.started.length).toBe(before + 1);
    expect(drops.live.get().get(running.id)?.failed).toBe(false);
    drops.dispose();
  });

  test("progress reaches the store at most four times a second", async () => {
    const running = drop("running", [file("a", 100)]);
    const { connection } = fake(() => ticket);
    const transfers = engine();
    const drops = new MacDrops(connection, transfers.value, shelf(), me, () => [], () => {});
    await drops.ready;
    drops.apply({ _tag: "Snapshot", drops: [running] });
    await settle();
    let published = 0;
    drops.live.subscribe(() => published++);
    const job = transfers.started[0]?.job ?? "";
    for (let done = 1; done <= 50; done++) transfers.emit({ type: "progress", job, done, total: 100, route: "lan" });
    expect(published).toBeLessThanOrEqual(1);
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(drops.live.get().get(running.id)).toEqual({ done: 50, total: 100, route: "lan", stalled: false, failed: false });
    drops.dispose();
  });

  test("sending offers the files, uploads once the Mac lets it run, and lists it as sent", async () => {
    const offered = drop("asking", [file("a", 10), file("b", 10)], "out");
    const { connection } = fake(() => ({ drop: offered, ticket }));
    const transfers = engine();
    const drops = new MacDrops(connection, transfers.value, shelf(), me, () => [], () => {});
    await drops.ready;
    await drops.send([
      { uri: "file:///a.mov", name: "a.mov", path: null, size: 10, mime: null },
      { uri: "file:///b.mov", name: "b.mov", path: null, size: 10, mime: null },
    ]);
    expect(transfers.started).toEqual([]);
    drops.apply({ _tag: "Changed", drop: { ...offered, state: "running" } });
    await settle();
    expect(transfers.started.map((job) => ("uri" in job ? job.uri : null))).toEqual(["file:///a.mov", "file:///b.mov"]);
    drops.apply({ _tag: "Changed", drop: { ...offered, state: "done" } });
    expect(drops.sent.get().map((sent) => sent.label)).toEqual(["2 files"]);
    drops.dispose();
  });

  test("an outgoing drop resumes after a restart from the saved file list", async () => {
    const offered = drop("asking", [file("a", 10)], "out");
    const saved = shelf();
    const first = fake(() => ({ drop: offered, ticket }));
    const before = new MacDrops(first.connection, engine().value, saved, me, () => [], () => {});
    await before.ready;
    await before.send([{ uri: "file:///a.mov", name: "a.mov", path: null, size: 10, mime: null }]);
    before.dispose();
    const transfers = engine();
    const after = new MacDrops(fake(() => ticket).connection, transfers.value, saved, me, () => [], () => {});
    await after.ready;
    after.apply({ _tag: "Snapshot", drops: [{ ...offered, state: "running" }] });
    await settle();
    expect(transfers.started.map((job) => ("uri" in job ? job.uri : null))).toEqual(["file:///a.mov"]);
    after.dispose();
  });

  test("after a restart, files already kept are confirmed again and the rest download, whatever the Mac counted as served", async () => {
    const saved = shelf();
    saved.write("received", JSON.stringify([{ id: "drop-0001/a", name: "a.mov", path: null, size: 10, mime: null, uri: "content://a", at: 1 }]));
    const running = drop("running", [file("a", 10, { done: 10 }), file("b", 10, { done: 10 })]);
    const { connection, calls } = fake((call) => (call.method === "drop.ticket" ? ticket : running));
    const transfers = engine();
    const drops = new MacDrops(connection, transfers.value, saved, me, () => [], () => {});
    await drops.ready;
    drops.apply({ _tag: "Snapshot", drops: [running] });
    await settle();
    expect(calls.find((call) => call.method === "drop.received")).toEqual({ method: "drop.received", payload: { id: running.id, fileId: "a", sha256: null } });
    expect(transfers.started.map((job) => job.fileId)).toEqual(["b"]);
    drops.dispose();
  });
});
