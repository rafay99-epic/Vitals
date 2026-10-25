import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  Alert,
  type CommandReceipt,
  type FromApp,
  type LiveSample,
  type Query,
  type QueryResult,
  type ToApp,
  FromApp as FromAppSchema,
  ToApp as ToAppSchema,
  VitalsRpc,
} from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";
import * as RpcClient from "effect/rpc/RpcClient";
import * as RpcSerialization from "effect/rpc/RpcSerialization";
import * as Socket from "effect/socket/Socket";

import { makeApp } from "../src/app.ts";
import { BridgeTransportService } from "../src/bridge/Bridge.ts";
import type { GatewayConfigShape } from "../src/config.ts";

export const OWNER = "owner@example.com";

const encodeFromApp = Schema.encodeSync(Schema.fromJsonString(FromAppSchema));
const decodeToApp = Schema.decodeUnknownSync(Schema.fromJsonString(ToAppSchema));

export const MAC = {
  name: "Test Mac",
  model: "Mac16,1",
  chip: "Apple M4",
  os: "macOS 27.0",
  coreCount: 10,
  memoryBytes: 17_179_869_184,
  hasBattery: true,
  hasFans: true,
  vitalsVersion: "0.0-test",
  channel: "dev" as const,
};

export const sample = (seq: number): LiveSample => ({
  seq,
  at: 1_790_000_000_000 + seq * 1000,
  cpu: { overall: 10 + seq, performance: null, efficiency: null, perCore: [] },
  memory: {
    totalBytes: 16,
    usedBytes: 8,
    appBytes: 4,
    wiredBytes: 2,
    compressedBytes: 1,
    cachedBytes: 1,
    freeBytes: 1,
    swapUsedBytes: 0,
    swapTotalBytes: 0,
    pressure: "normal",
  },
});

export class FakeApp {
  readonly received: Array<ToApp> = [];
  readonly holdCommands = new Set<string>();
  invalidReplies = false;
  silentQueries = false;
  /** Answers queries the fake doesn't know; return null to fall through to the defaults. */
  answer: ((q: Query) => QueryResult | Promise<QueryResult> | null) | null = null;
  private readonly queue = Effect.runSync(Queue.unbounded<string>());

  readonly lines: Stream.Stream<string> = Stream.fromQueue(this.queue);

  emit(message: FromApp): void {
    Effect.runSync(Queue.offer(this.queue, encodeFromApp(message)));
  }

  write = (line: string): void => {
    const message = decodeToApp(line);
    this.received.push(message);
    switch (message.t) {
      case "hello":
        this.emit({ t: "hello", v: 1, mac: MAC, keepAwake: { active: false, display: false, until: null, whileProcess: null } });
        break;
      case "cmd": {
        const base: CommandReceipt = {
          id: message.id,
          kind: message.command._tag,
          deviceId: message.deviceId,
          status: "pending",
          createdAt: Date.now(),
          deadlineAt: Date.now() + 10_000,
          finishedAt: null,
          error: null,
        };
        if (this.holdCommands.has(message.command._tag)) {
          this.emit({ t: "receipt", receipt: base });
        } else {
          this.emit({ t: "receipt", receipt: { ...base, status: "done", deadlineAt: null, finishedAt: Date.now() } });
        }
        break;
      }
      case "cancel":
        this.emit({
          t: "receipt",
          receipt: {
            id: message.id,
            kind: "ShutDown",
            deviceId: this.lastDevice(),
            status: "cancelled",
            createdAt: Date.now(),
            deadlineAt: null,
            finishedAt: Date.now(),
            error: null,
          },
        });
        break;
      case "query":
        if (this.silentQueries) break;
        {
          const custom = this.answer?.(message.q) ?? null;
          if (custom !== null) {
            void Promise.resolve(custom).then((ok) => this.emit({ t: "result", id: message.id, ok, error: null }));
            break;
          }
        }
        if (message.q._tag === "Apps" && this.invalidReplies) {
          const running = [{ pid: -1, bundleId: null, name: "Launching", active: false, hidden: false }];
          const ok = { _tag: "Apps", result: { running, emulators: [] } };
          Effect.runSync(Queue.offer(this.queue, JSON.stringify({ t: "result", id: message.id, ok, error: null })));
        } else if (message.q._tag === "Apps") {
          this.emit({ t: "result", id: message.id, ok: { _tag: "Apps", result: { running: [], emulators: [] } }, error: null });
        } else {
          this.emit({ t: "result", id: message.id, ok: null, error: "not in fake" });
        }
        break;
      default:
        break;
    }
  };

  private lastDevice() {
    const cmd = this.received.toReversed().find((message) => message.t === "cmd");
    if (cmd === undefined || cmd.t !== "cmd") throw new Error("no command yet");
    return cmd.deviceId;
  }

  needs() {
    return this.received.filter((message): message is Extract<ToApp, { t: "need" }> => message.t === "need");
  }

  adminResults() {
    return this.received.filter((message): message is Extract<ToApp, { t: "adminResult" }> => message.t === "adminResult");
  }
}

let nextPort = 48_200 + Math.floor(Math.random() * 500);

export const startGateway = async (dataDir = mkdtempSync(join(tmpdir(), "vitals-gateway-"))) => {
  const port = nextPort;
  nextPort += 1;
  const config: GatewayConfigShape = {
    channel: "dev",
    port,
    servePort: 7999,
    dataDir,
    webDir: null,
    tailscaleBin: null,
    manageServe: false,
    ownerLogin: OWNER,
    lanPort: port + 2_000,
  };
  const app = new FakeApp();
  const transport = Layer.succeed(BridgeTransportService, { lines: app.lines, write: app.write, onClose: () => {} });
  const dispose = Effect.runFork(
    Layer.launch(
      makeApp(config, { transport }),
    ),
  );
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const ok = await fetch(`${base}/api/health`).then((response) => response.ok).catch(() => false);
    if (ok) break;
    await Bun.sleep(20);
  }
  return {
    app,
    base,
    lanBase: `http://127.0.0.1:${port + 2_000}`,
    dataDir,
    stop: async (keepData = false) => {
      await Effect.runPromise(Fiber.interrupt(dispose));
      if (!keepData) rmSync(dataDir, { recursive: true, force: true });
    },
  };
};

export const ownerHeaders = { "tailscale-user-login": OWNER, "content-type": "application/json" };

export const adminOp = async (app: FakeApp, op: Extract<FromApp, { t: "admin" }>["op"]) => {
  const id = `admin-${Math.random()}`;
  app.emit({ t: "admin", id, op });
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const result = app.adminResults().find((message) => message.id === id);
    if (result !== undefined) return result;
    await Bun.sleep(10);
  }
  throw new Error("admin op timed out");
};

export const alertFixture = (id: string) =>
  Schema.decodeUnknownSync(Alert)({
    id,
    rule: "agentOverload",
    severity: "warning",
    summary: "6 agents",
    raisedAt: Date.now(),
    clearedAt: null,
    groups: [],
    plan: { actions: [], summary: "Lower priority" },
  });

export const pairDevice = async (gateway: Awaited<ReturnType<typeof startGateway>>) => {
  const created = await adminOp(gateway.app, { _tag: "CreatePairing" });
  if (created.ok?._tag !== "CreatePairing") throw new Error("pairing not created");
  const response = await fetch(`${gateway.base}/api/pair`, {
    method: "POST",
    headers: ownerHeaders,
    body: JSON.stringify({ code: created.ok.code, device: { name: "Pixel 9", platform: "android", model: "Pixel 9", appVersion: "1.0.0" } }),
  });
  if (!response.ok) throw new Error(`pair failed ${response.status}`);
  return (await response.json()) as { deviceId: string; token: string; scopes: Array<string> };
};

export const ticketFor = async (base: string, token: string) => {
  const response = await fetch(`${base}/api/ws-ticket`, {
    method: "POST",
    headers: { ...ownerHeaders, authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`ticket failed ${response.status}`);
  return ((await response.json()) as { ticket: string }).ticket;
};

const bunWebSocketConstructor = Layer.succeed(Socket.WebSocketConstructor)((url, options) => {
  if (typeof options === "object" && !Array.isArray(options)) {
    const bunOptions: Bun.WebSocketOptions = options.headers === undefined ? {} : { headers: options.headers };
    return new WebSocket(url, bunOptions);
  }
  return new WebSocket(url, options);
});

export const clientLayer = (base: string, ticket: string) =>
  Layer.effect(RpcClient.Protocol, RpcClient.makeProtocolSocket({ retryTransientErrors: false })).pipe(
    Layer.provide(
      Layer.mergeAll(
        Socket.layerWebSocket(`${base.replace("http", "ws")}/ws?v=1&ticket=${ticket}&client=test`, {
          headers: { "tailscale-user-login": OWNER },
        }).pipe(Layer.provide(bunWebSocketConstructor)),
        RpcSerialization.layerJson,
      ),
    ),
  );

export const makeClient = RpcClient.make(VitalsRpc);

export type Gateway = Awaited<ReturnType<typeof startGateway>>;

/** Runs `body` against a fresh RPC connection as the device holding `token`. */
export const withClient = async <A>(
  gateway: Gateway,
  token: string,
  body: (client: Effect.Success<typeof makeClient>) => Effect.Effect<A, unknown>,
) => {
  const ticket = await ticketFor(gateway.base, token);
  return Effect.runPromise(Effect.scoped(Effect.flatMap(makeClient, body)).pipe(Effect.provide(clientLayer(gateway.base, ticket))));
};
