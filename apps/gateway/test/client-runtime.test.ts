import { afterEach, describe, expect, test } from "bun:test";

import { type ConnectionState, createConnection, pair, parsePairingUrl } from "@vitals/client-runtime";

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
    const connection = createConnection({
      baseUrl: gateway.base,
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
      { name: "Test phone", platform: "web", model: "Browser", appVersion: "1.0.0" },
      withOwner,
    );
    if (!paired.ok) throw new Error(paired.message);
    const connection = createConnection({
      baseUrl: gateway.base,
      token: paired.response.token,
      clientVersion: "test",
      webSocket: ownerSocket,
      fetch: withOwner,
      random: () => 0,
    });
    await until(() => connection.state.get()._tag === "Ready");
    await adminOp(gateway.app, { _tag: "RevokeDevice", deviceId: paired.response.deviceId });
    await until(() => connection.state.get()._tag === "Revoked", 8000);
    connection.dispose();
  });
});
