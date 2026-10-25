import { Database } from "bun:sqlite";
import { afterEach, describe, expect, test } from "bun:test";
import { join } from "node:path";

import { CommandId } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { MAX_FRAME_BYTES } from "../src/config.ts";
import { adminOp, alertFixture, clientLayer, makeClient, ownerHeaders, pairDevice, sample, startGateway, ticketFor } from "./harness.ts";

const commandId = Schema.decodeUnknownSync(CommandId);
let gateway: Awaited<ReturnType<typeof startGateway>> | null = null;

afterEach(async () => {
  await gateway?.stop();
  gateway = null;
});

const withClient = async <A>(token: string, body: (client: Effect.Success<typeof makeClient>) => Effect.Effect<A, unknown>) => {
  if (gateway === null) throw new Error("no gateway");
  const ticket = await ticketFor(gateway.base, token);
  return Effect.runPromise(
    Effect.scoped(Effect.flatMap(makeClient, body)).pipe(Effect.provide(clientLayer(gateway.base, ticket))),
  );
};

describe("pairing and auth", () => {
  test("pairs with a one-time code and rejects reuse", async () => {
    gateway = await startGateway();
    const created = await adminOp(gateway.app, { _tag: "CreatePairing" });
    if (created.ok?._tag !== "CreatePairing") throw new Error("no pairing");
    const body = JSON.stringify({
      code: created.ok.code,
      device: { name: "Pixel", platform: "android", model: "P9", appVersion: "1" },
    });
    const first = await fetch(`${gateway.base}/api/pair`, { method: "POST", headers: ownerHeaders, body });
    expect(first.status).toBe(200);
    const paired = (await first.json()) as { scopes: Array<string> };
    expect(paired.scopes).toEqual(["read", "operate", "files", "fsRead"]);
    const second = await fetch(`${gateway.base}/api/pair`, { method: "POST", headers: ownerHeaders, body });
    expect(second.status).toBe(401);
  });

  test("web pairing keeps the token in an HttpOnly cookie", async () => {
    gateway = await startGateway();
    const created = await adminOp(gateway.app, { _tag: "CreatePairing" });
    if (created.ok?._tag !== "CreatePairing") throw new Error("no pairing");
    const paired = await fetch(`${gateway.base}/api/pair`, {
      method: "POST",
      headers: ownerHeaders,
      body: JSON.stringify({ code: created.ok.code, device: { name: "Browser", platform: "web", model: "Mac", appVersion: "1" } }),
    });
    expect(paired.status).toBe(200);
    expect(((await paired.json()) as { token: string | null }).token).toBeNull();
    const setCookie = paired.headers.get("set-cookie") ?? "";
    expect(setCookie).toMatch(/^vitals_session_dev=[^;]+;/);
    expect(setCookie).toContain("HttpOnly");
    expect(setCookie).toContain("Secure");
    expect(setCookie).toContain("SameSite=Strict");
    expect(setCookie).toContain("Path=/api");
    const cookie = { ...ownerHeaders, cookie: setCookie.split(";")[0] ?? "" };

    const session = await fetch(`${gateway.base}/api/session`, { headers: cookie });
    expect(session.status).toBe(200);
    expect(((await session.json()) as { scopes: Array<string> }).scopes).toEqual(["read", "operate", "files"]);
    const crossSite = await fetch(`${gateway.base}/api/ws-ticket`, { method: "POST", headers: { ...cookie, "sec-fetch-site": "cross-site" } });
    expect(crossSite.status).toBe(403);
    const ticket = await fetch(`${gateway.base}/api/ws-ticket`, { method: "POST", headers: { ...cookie, "sec-fetch-site": "same-origin" } });
    expect(ticket.status).toBe(200);

    const second = await adminOp(gateway.app, { _tag: "CreatePairing" });
    if (second.ok?._tag !== "CreatePairing") throw new Error("no second pairing");
    const repaired = await fetch(`${gateway.base}/api/pair`, {
      method: "POST",
      headers: cookie,
      body: JSON.stringify({ code: second.ok.code, device: { name: "Browser", platform: "web", model: "Mac", appVersion: "1" } }),
    });
    expect(repaired.status).toBe(200);
    expect((await fetch(`${gateway.base}/api/session`, { headers: cookie })).status).toBe(204);
    const fresh = { ...ownerHeaders, cookie: (repaired.headers.get("set-cookie") ?? "").split(";")[0] ?? "" };
    expect((await fetch(`${gateway.base}/api/session`, { headers: fresh })).status).toBe(200);

    const unpaired = await fetch(`${gateway.base}/api/unpair`, { method: "POST", headers: fresh });
    expect(unpaired.status).toBe(200);
    expect(unpaired.headers.get("set-cookie")).toContain("Max-Age=0");
    expect((await fetch(`${gateway.base}/api/session`, { headers: fresh })).status).toBe(204);
    expect((await fetch(`${gateway.base}/api/session`, { headers: ownerHeaders })).status).toBe(204);
  });

  test("parallel re-pairs from one browser leave exactly one session valid", async () => {
    const started = await startGateway();
    gateway = started;
    const pairWeb = async (headers: Record<string, string>) => {
      const created = await adminOp(started.app, { _tag: "CreatePairing" });
      if (created.ok?._tag !== "CreatePairing") throw new Error("no pairing");
      return fetch(`${started.base}/api/pair`, {
        method: "POST",
        headers,
        body: JSON.stringify({ code: created.ok.code, device: { name: "Browser", platform: "web", model: "Mac", appVersion: "1" } }),
      });
    };
    const cookieOf = (response: Response) => ({ ...ownerHeaders, cookie: (response.headers.get("set-cookie") ?? "").split(";")[0] ?? "" });
    const original = cookieOf(await pairWeb(ownerHeaders));
    const [first, second] = await Promise.all([pairWeb(original), pairWeb(original)]);
    if (first === undefined || second === undefined) throw new Error("missing response");
    const statuses = await Promise.all(
      [original, cookieOf(first), cookieOf(second)].map(async (headers) => (await fetch(`${started.base}/api/session`, { headers })).status),
    );
    expect(statuses[0]).toBe(204);
    expect(statuses.slice(1).filter((status) => status === 200).length).toBe(1);
  });

  test("open alerts lists alerts raised after a sequence that are still open", async () => {
    gateway = await startGateway();
    const { token } = await pairDevice(gateway);
    const first = alertFixture("alert-a");
    const second = alertFixture("alert-b");
    gateway.app.emit({ t: "event", event: { _tag: "AlertRaised", at: Date.now(), alert: first } });
    gateway.app.emit({ t: "event", event: { _tag: "AlertRaised", at: Date.now(), alert: second } });
    gateway.app.emit({ t: "event", event: { _tag: "AlertCleared", at: Date.now(), alert: first } });
    await Bun.sleep(100);
    const read = async (after: number) => {
      const response = await fetch(`${gateway?.base}/api/alerts?after=${after}`, { headers: { ...ownerHeaders, authorization: `Bearer ${token}` } });
      return (await response.json()) as { lastSeq: number; alerts: Array<{ id: string }> };
    };
    const all = await read(0);
    expect(all.alerts.map((alert) => alert.id)).toEqual(["alert-b"]);
    expect((await read(all.lastSeq)).alerts).toEqual([]);
    expect((await fetch(`${gateway.base}/api/alerts`, { headers: ownerHeaders })).status).toBe(401);
    const hello = await withClient(token, (client) => client["server.hello"]({}));
    expect(hello.alerts.map((alert) => alert.id)).toEqual([second.id]);
    expect(hello.lastEventSeq).toBe(all.lastSeq);
  });

  test("rejects a foreign tailnet identity", async () => {
    gateway = await startGateway();
    const response = await fetch(`${gateway.base}/api/ws-ticket`, {
      method: "POST",
      headers: { "tailscale-user-login": "stranger@example.com", authorization: "Bearer x" },
    });
    expect(response.status).toBe(403);
  });

  test("websocket upgrade needs protocol version and ticket", async () => {
    gateway = await startGateway();
    const wrongVersion = await fetch(`${gateway.base}/ws?v=999`, { headers: ownerHeaders });
    expect(wrongVersion.status).toBe(426);
    const noTicket = await fetch(`${gateway.base}/ws?v=1`, { headers: ownerHeaders });
    expect(noTicket.status).toBe(401);
  });
});

describe("rpc over websocket", () => {
  test("hello reports the Mac and live samples flow with only requested topics", async () => {
    gateway = await startGateway();
    const { token } = await pairDevice(gateway);
    const app = gateway.app;
    const result = await withClient(token, (client) =>
      Effect.gen(function* () {
        const hello = yield* client["server.hello"]({});
        yield* Effect.sync(() => {
          setTimeout(() => app.emit({ t: "sample", data: sample(1) }), 50);
          setTimeout(() => app.emit({ t: "sample", data: sample(2) }), 100);
        });
        const samples = yield* client["stats.live"]({ topics: ["cpu"] }).pipe(Stream.take(2), Stream.runCollect);
        return { hello, samples };
      }),
    );
    expect(result.hello.mac?.chip).toBe("Apple M4");
    const values = [...result.samples];
    expect(values.length).toBe(2);
    expect(values[0]?.cpu?.overall).toBeGreaterThan(0);
    expect(values[0]?.memory).toBeUndefined();
    expect(gateway.app.needs().some((need) => need.topics.includes("cpu"))).toBe(true);
    await Bun.sleep(50);
    expect(gateway.app.needs().at(-1)?.topics).toEqual([]);
  });

  test("commands are idempotent and destructive ones need the scope", async () => {
    gateway = await startGateway();
    const { token, deviceId } = await pairDevice(gateway);
    const id = commandId("cmd-keep-awake");
    const outcome = await withClient(token, (client) =>
      Effect.gen(function* () {
        const first = yield* client["command.run"]({
          commandId: id,
          command: { _tag: "KeepAwake", until: null, display: false, whileProcess: null },
        });
        const again = yield* client["command.run"]({ commandId: id, command: { _tag: "AllowSleep" } });
        const denied = yield* client["command.run"]({
          commandId: commandId("cmd-shutdown"),
          command: { _tag: "ShutDown", graceSeconds: 10 },
        }).pipe(Effect.flip);
        return { first, again, denied };
      }),
    );
    expect(outcome.first.status).toBe("done");
    expect(outcome.again.kind).toBe("KeepAwake");
    expect(outcome.denied._tag).toBe("AuthError");
    expect(gateway.app.received.filter((message) => message.t === "cmd").length).toBe(1);

    await adminOp(gateway.app, { _tag: "SetScopes", deviceId: deviceId as never, scopes: ["read", "operate", "destructive"] });
    gateway.app.holdCommands.add("ShutDown");
    const cancelled = await withClient(token, (client) =>
      Effect.gen(function* () {
        const pending = yield* client["command.run"]({
          commandId: commandId("cmd-shutdown-2"),
          command: { _tag: "ShutDown", graceSeconds: 10 },
        });
        const cancel = yield* client["command.cancel"]({ commandId: pending.id });
        return { pending, cancel };
      }),
    );
    expect(cancelled.pending.status).toBe("pending");
    expect(cancelled.cancel.status).toBe("cancelled");
  });

  test("an invalid reply from Vitals fails the query without waiting for the timeout", async () => {
    gateway = await startGateway();
    const { token } = await pairDevice(gateway);
    gateway.app.invalidReplies = true;
    const started = Date.now();
    const error = await withClient(token, (client) => Effect.flip(client["apps.list"]({})));
    expect(error._tag).toBe("Unavailable");
    expect(Date.now() - started).toBeLessThan(2000);
  });

  test("an oversized or garbage frame drops that socket and nothing else", async () => {
    gateway = await startGateway();
    const { token } = await pairDevice(gateway);
    const open = async (payload: string) => {
      const ticket = await ticketFor(gateway?.base ?? "", token);
      const socket = new WebSocket(`${gateway?.base.replace("http", "ws")}/ws?v=1&ticket=${ticket}&client=fuzz`, {
        headers: ownerHeaders,
      });
      await new Promise((resolve) => socket.addEventListener("open", resolve, { once: true }));
      const closed = new Promise<number>((resolve) => socket.addEventListener("close", (event) => resolve(event.code), { once: true }));
      socket.send(payload);
      return Promise.race([closed, Bun.sleep(2000).then(() => -1)]).finally(() => socket.close());
    };
    expect(await open("x".repeat(MAX_FRAME_BYTES + 1))).not.toBe(-1);
    await open("{not json");
    await open(JSON.stringify({ _tag: "Request", id: "1", tag: "no.such.method", payload: {}, headers: [] }));
    expect((await fetch(`${gateway.base}/api/health`)).status).toBe(200);
    const hello = await withClient(token, (client) => client["server.hello"]({}));
    expect(hello.protocol).toBe(1);
  });

  test("revoking a device closes its live socket", async () => {
    gateway = await startGateway();
    const { token, deviceId } = await pairDevice(gateway);
    const app = gateway.app;
    const ended = withClient(token, (client) =>
      client["system.events"]({ afterSeq: null }).pipe(Stream.runDrain, Effect.as("ended"), Effect.catch(() => Effect.succeed("errored"))),
    );
    await Bun.sleep(150);
    await adminOp(app, { _tag: "RevokeDevice", deviceId: deviceId as never });
    expect(await Promise.race([ended, Bun.sleep(3000).then(() => "timeout")])).not.toBe("timeout");
    const response = await fetch(`${gateway.base}/api/ws-ticket`, {
      method: "POST",
      headers: { ...ownerHeaders, authorization: `Bearer ${token}` },
    });
    expect(response.status).toBe(401);
  });

  test("events replay after a sequence and every frame lands in activity.db", async () => {
    gateway = await startGateway();
    const { token } = await pairDevice(gateway);
    gateway.app.emit({ t: "event", event: { _tag: "WillSleep", at: 1 } });
    gateway.app.emit({ t: "event", event: { _tag: "DidWake", at: 2 } });
    await Bun.sleep(100);
    const replayed = await withClient(token, (client) =>
      client["system.events"]({ afterSeq: 1 }).pipe(Stream.take(1), Stream.runCollect),
    );
    expect([...replayed][0]?.event._tag).toBe("DidWake");
    await Bun.sleep(400);
    const db = new Database(join(gateway.dataDir, "activity.db"), { readonly: true });
    const frames = db.query("SELECT count(*) AS n FROM frames").get() as { n: number };
    const kinds = db.query("SELECT DISTINCT kind FROM events").all().map((row) => (row as { kind: string }).kind);
    db.close();
    expect(frames.n).toBeGreaterThan(0);
    expect(kinds).toContain("ws.opened");
    expect(kinds).toContain("pairing.consumed");
    expect(kinds).toContain("mac.willSleep");
  });

  test("a client that fell far behind replays every missed event in order", async () => {
    gateway = await startGateway();
    const { token } = await pairDevice(gateway);
    for (let at = 1; at <= 300; at += 1) gateway.app.emit({ t: "event", event: { _tag: "DidWake", at: Date.now() + at } });
    await Bun.sleep(300);
    const replayed = await withClient(token, (client) => client["system.events"]({ afterSeq: 0 }).pipe(Stream.take(300), Stream.runCollect));
    const seqs = [...replayed].map((item) => item.seq);
    expect(seqs.length).toBe(300);
    expect(seqs.every((seq, index) => index === 0 || seq === (seqs[index - 1] ?? 0) + 1)).toBe(true);
  });

  test("a countdown left open when the Mac went down is closed on restart", async () => {
    const first = await startGateway();
    gateway = first;
    const { token, deviceId } = await pairDevice(first);
    await adminOp(first.app, { _tag: "SetScopes", deviceId: deviceId as never, scopes: ["read", "operate", "destructive"] });
    first.app.holdCommands.add("ShutDown");
    const pending = await withClient(token, (client) =>
      client["command.run"]({ commandId: commandId("cmd-shutdown-gone"), command: { _tag: "ShutDown", graceSeconds: 10 } }),
    );
    expect(pending.status).toBe("pending");
    gateway = null;
    await first.stop(true);
    const db = new Database(join(first.dataDir, "remote.db"));
    db.run("UPDATE commands SET deadline_at = ? WHERE id = ?", [Date.now() - 60_000, pending.id]);
    db.close();
    gateway = await startGateway(first.dataDir);
    const replayed = await withClient(token, (client) => client["command.log"]({}).pipe(Stream.take(1), Stream.runCollect));
    expect([...replayed][0]).toMatchObject({ id: pending.id, status: "failed" });
  });

  test("alerts left open by a previous Vitals run are cleared on restart", async () => {
    const first = await startGateway();
    const alert = alertFixture("alert-1");
    first.app.emit({ t: "event", event: { _tag: "AlertRaised", at: alert.raisedAt, alert } });
    await Bun.sleep(100);
    await first.stop(true);
    gateway = await startGateway(first.dataDir);
    const { token } = await pairDevice(gateway);
    const replayed = await withClient(token, (client) =>
      client["system.events"]({ afterSeq: 0 }).pipe(Stream.take(2), Stream.runCollect),
    );
    const last = [...replayed].at(-1)?.event;
    expect(last?._tag).toBe("AlertCleared");
    expect(last?._tag === "AlertCleared" ? last.alert.id : null).toBe(alert.id);
  });
});
