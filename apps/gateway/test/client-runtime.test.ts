import { afterEach, describe, expect, test } from "bun:test";

import { type ConnectionState, type Route, createConnection, pair, pairOverLan, parsePairingUrl, probeLan } from "@vitals/client-runtime";
import { fromBase64Url, generateKeyPair } from "@vitals/noise";

import { OWNER, adminOp, sample, startGateway } from "./harness.ts";

let gateway: Awaited<ReturnType<typeof startGateway>> | null = null;

afterEach(async () => {
  await gateway?.stop();
  gateway = null;
});

const withOwner: typeof fetch = Object.assign(
  (input: string | URL | Request, init?: RequestInit) =>
    fetch(input, { ...init, headers: { ...Object.fromEntries(new Headers(init?.headers).entries()), "tailscale-user-login": OWNER } }),
  { preconnect: fetch.preconnect },
);

const ownerSocket = (url: string) => new WebSocket(url, { headers: { "tailscale-user-login": OWNER } });

const rawSocket = (url: string) => {
  const socket = new WebSocket(url);
  socket.binaryType = "arraybuffer";
  return socket;
};

const phone = { name: "Pixel 9", platform: "android", model: "Pixel 9", appVersion: "1.0.0" } as const;

const lanPort = (lanBase: string) => Number(new URL(lanBase).port);

const pairByWifi = async (running: NonNullable<typeof gateway>, allow: boolean) => {
  const port = lanPort(running.lanBase);
  const advert = await probeLan("127.0.0.1", port, null, fetch);
  if (advert === null) throw new Error("no LAN advert");
  const device = generateKeyPair();
  const codes: Array<string> = [];
  const attempt = pairOverLan({
    host: "127.0.0.1",
    port,
    macKey: fromBase64Url(advert.key),
    device,
    info: phone,
    raw: rawSocket,
    onWaiting: (code) => codes.push(code),
  });
  await until(() => codes.length === 1 && running.app.received.some((message) => message.t === "pairPrompt"));
  const prompt = running.app.received.find((message) => message.t === "pairPrompt");
  if (prompt?.t !== "pairPrompt") throw new Error("no prompt");
  expect(prompt.prompt.code).toBe(codes[0] ?? "");
  expect(prompt.prompt.device.name).toBe("Pixel 9");
  await adminOp(running.app, { _tag: "ResolvePairPrompt", id: prompt.prompt.id, allow });
  return { outcome: await attempt.outcome, device, key: advert.key, port };
};

const until = async (check: () => boolean, ms = 4000) => {
  const started = Date.now();
  while (!check()) {
    if (Date.now() - started > ms) throw new Error("condition not met in time");
    await Bun.sleep(20);
  }
};

describe("client runtime against the gateway", () => {
  test("pairs from a QR link, reaches Ready, streams, suspends and wakes", async () => {
    gateway = await startGateway();
    const created = await adminOp(gateway.app, { _tag: "CreatePairing" });
    if (created.ok?._tag !== "CreatePairing") throw new Error("no pairing");
    const link = parsePairingUrl(`${gateway.base}/pair#code=${created.ok.code}`);
    expect(link?.code).toBe(created.ok.code);
    if (link === null) throw new Error("bad link");
    const paired = await pair(link, { name: "Test phone", platform: "android", model: "Emu", appVersion: "1.0.0" }, withOwner);
    if (!paired.ok) throw new Error(paired.message);

    const transitions: Array<ConnectionState["_tag"]> = [];
    const base = gateway.base;
    const connection = createConnection({
      routes: () => [{ _tag: "Tailnet", baseUrl: base }],
      token: paired.response.token,
      clientVersion: "test",
      webSocket: ownerSocket,
      fetch: withOwner,
      onTransition: (_, next) => transitions.push(next._tag),
    });
    await until(() => connection.state.get()._tag === "Ready");

    const seen: Array<number> = [];
    const stop = connection.watch((client) => client["stats.live"]({ topics: ["cpu"] }), (value) => seen.push(value.seq));
    await Bun.sleep(100);
    gateway.app.emit({ t: "sample", data: sample(41) });
    await until(() => seen.includes(41));

    connection.suspend();
    await until(() => connection.state.get()._tag === "Suspended");
    connection.wake("foreground");
    await until(() => connection.state.get()._tag === "Ready");
    gateway.app.emit({ t: "sample", data: sample(42) });
    await until(() => seen.includes(42));

    const result = await connection.call((client) => client["apps.list"]({}));
    expect(result.ok).toBe(true);
    stop();
    connection.dispose();
    expect(transitions).toContain("Suspended");
  });

  test("a revoked device lands in Revoked instead of retrying forever", async () => {
    gateway = await startGateway();
    const created = await adminOp(gateway.app, { _tag: "CreatePairing" });
    if (created.ok?._tag !== "CreatePairing") throw new Error("no pairing");
    const paired = await pair(
      { baseUrl: gateway.base, code: created.ok.code },
      { name: "Test phone", platform: "android", model: "Pixel", appVersion: "1.0.0" },
      withOwner,
    );
    if (!paired.ok) throw new Error(paired.message);
    const base = gateway.base;
    const connection = createConnection({
      routes: () => [{ _tag: "Tailnet", baseUrl: base }],
      token: paired.response.token,
      clientVersion: "test",
      webSocket: ownerSocket,
      fetch: withOwner,
      random: () => 0,
    });
    await until(() => connection.state.get()._tag === "Ready");
    gateway.app.silentQueries = true;
    const inFlight = connection.call((client) => client["apps.list"]({}));
    await Bun.sleep(100);
    await adminOp(gateway.app, { _tag: "RevokeDevice", deviceId: paired.response.deviceId });
    await until(() => connection.state.get()._tag === "Revoked", 8000);
    expect((await inFlight).ok).toBe(false);
    connection.dispose();
  });

  test("pairs over Wi-Fi once the Mac allows it, then connects and streams on the Wi-Fi route", async () => {
    gateway = await startGateway();
    const running = gateway;
    const { outcome, device, key, port } = await pairByWifi(running, true);
    if (!outcome.ok) throw new Error(outcome.reason);
    expect(outcome.result.routes.key).toBe(key);
    expect(running.app.received.some((message) => message.t === "pairPromptEnded")).toBe(true);

    const connection = createConnection({
      routes: () => [{ _tag: "Lan", host: "127.0.0.1", port }],
      token: outcome.result.token,
      macKey: () => key,
      deviceKey: device,
      clientVersion: "test",
      webSocket: rawSocket,
    });
    await until(() => connection.state.get()._tag === "Ready");
    const ready = connection.state.get();
    expect(ready._tag === "Ready" ? ready.route : null).toBe("lan");
    expect(ready._tag === "Ready" ? ready.hello.routes?.key : null).toBe(key);

    const seen: Array<number> = [];
    const stop = connection.watch((client) => client["stats.live"]({ topics: ["cpu"] }), (value) => seen.push(value.seq));
    await Bun.sleep(100);
    running.app.emit({ t: "sample", data: sample(51) });
    await until(() => seen.includes(51));
    expect((await connection.call((client) => client["apps.list"]({}))).ok).toBe(true);
    stop();
    connection.dispose();
  });

  test("a denied Wi-Fi pairing creates no device", async () => {
    gateway = await startGateway();
    const { outcome } = await pairByWifi(gateway, false);
    expect(outcome).toEqual({ ok: false, reason: "denied" });
    const listed = await adminOp(gateway.app, { _tag: "ListDevices" });
    expect(listed.ok?._tag === "ListDevices" ? listed.ok.devices.length : -1).toBe(0);
  });

  test("prefers Wi-Fi when both routes answer and falls back to Tailscale when Wi-Fi is gone", async () => {
    gateway = await startGateway();
    const running = gateway;
    const { outcome, device, key, port } = await pairByWifi(running, true);
    if (!outcome.ok) throw new Error(outcome.reason);
    const both: ReadonlyArray<Route> = [
      { _tag: "Lan", host: "127.0.0.1", port },
      { _tag: "Tailnet", baseUrl: running.base },
    ];
    const options = { token: outcome.result.token, macKey: () => key, deviceKey: device, clientVersion: "test", webSocket: ownerSocket, fetch: withOwner };
    const preferred = createConnection({ ...options, routes: () => both });
    await until(() => preferred.state.get()._tag === "Ready");
    const first = preferred.state.get();
    expect(first._tag === "Ready" ? first.route : null).toBe("lan");
    preferred.dispose();

    const fallback = createConnection({ ...options, routes: () => [{ _tag: "Lan", host: "127.0.0.1", port: port + 7 }, { _tag: "Tailnet", baseUrl: running.base }] });
    await until(() => fallback.state.get()._tag === "Ready", 6000);
    const second = fallback.state.get();
    expect(second._tag === "Ready" ? second.route : null).toBe("tailnet");
    fallback.dispose();
  });

  test("a phone pinned to a different Mac key never connects over Wi-Fi", async () => {
    gateway = await startGateway();
    const { outcome, device, port } = await pairByWifi(gateway, true);
    if (!outcome.ok) throw new Error(outcome.reason);
    const impostorKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    const connection = createConnection({
      routes: () => [{ _tag: "Lan", host: "127.0.0.1", port }],
      token: outcome.result.token,
      macKey: () => impostorKey,
      deviceKey: device,
      clientVersion: "test",
      webSocket: rawSocket,
      random: () => 0,
    });
    await until(() => connection.state.get()._tag === "Backoff");
    const state = connection.state.get();
    expect(state._tag === "Backoff" ? state.failures[0]?.kind : null).toBe("lan");
    connection.dispose();
  });

  test("moves a live session from Tailscale to Wi-Fi without dropping the stream", async () => {
    gateway = await startGateway();
    const running = gateway;
    const { outcome, device, key, port } = await pairByWifi(running, true);
    if (!outcome.ok) throw new Error(outcome.reason);
    let lanPortNow = port + 7;
    const connection = createConnection({
      routes: () => [
        { _tag: "Lan", host: "127.0.0.1", port: lanPortNow },
        { _tag: "Tailnet", baseUrl: running.base },
      ],
      token: outcome.result.token,
      macKey: () => key,
      deviceKey: device,
      clientVersion: "test",
      webSocket: ownerSocket,
      fetch: withOwner,
    });
    await until(() => connection.state.get()._tag === "Ready", 6000);
    const before = connection.state.get();
    expect(before._tag === "Ready" ? before.route : null).toBe("tailnet");

    const tags: Array<string> = [];
    const unsubscribe = connection.state.subscribe(() => tags.push(connection.state.get()._tag));
    const seen: Array<number> = [];
    const stop = connection.watch((client) => client["stats.live"]({ topics: ["cpu"] }), (value) => seen.push(value.seq));
    await Bun.sleep(100);
    running.app.emit({ t: "sample", data: sample(61) });
    await until(() => seen.includes(61));

    lanPortNow = port;
    connection.wake("network");
    await until(() => {
      const now = connection.state.get();
      return now._tag === "Ready" && now.route === "lan";
    }, 6000);
    expect(tags.filter((tag) => tag !== "Ready")).toEqual([]);
    await Bun.sleep(150);
    running.app.emit({ t: "sample", data: sample(62) });
    await until(() => seen.includes(62));
    unsubscribe();
    stop();
    connection.dispose();
  });
});
