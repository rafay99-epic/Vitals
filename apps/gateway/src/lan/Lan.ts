import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { networkInterfaces } from "node:os";
import { join } from "node:path";

import {
  type DeviceInfo,
  type LanAccept,
  type LanAdvert,
  type LanEndpoint,
  type LanPairResult,
  type LanTls,
  type MacRoutes,
  pairedScopes,
  DROP_LAN_TLS_OFFSET,
  LAN_PROLOGUE,
  LanOpen,
  PAIR_REQUEST_TTL_MS,
  PROTOCOL_VERSION,
} from "@vitals/contracts";
import { newId } from "@vitals/shared";
import { type KeyPair, type Transport, keyPairFromSecret, matchCode, responder, toBase64Url } from "@vitals/noise";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";
import * as SubscriptionRef from "effect/SubscriptionRef";
import type { ServerWebSocket } from "bun";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Auth } from "../auth/Auth.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { GatewayConfig, MAX_FRAME_BYTES } from "../config.ts";
import { DropStore } from "../drop/DropStore.ts";
import { loadTlsIdentity } from "../drop/tls.ts";
import { Store } from "../persistence/Store.ts";
import { LOOPBACK_HEADER } from "../ws/route.ts";

export interface LanInfo {
  readonly port: number;
  readonly key: string;
}

export class Lan extends Context.Service<
  Lan,
  {
    readonly info: LanInfo | null;
    readonly reachable: Effect.Effect<boolean>;
    readonly reachableChanges: Stream.Stream<boolean>;
    readonly endpoints: () => ReadonlyArray<LanEndpoint>;
    readonly routes: (tailnet: string | null) => MacRoutes | null;
    readonly resolvePrompt: (id: string, allow: boolean) => boolean;
  }
>()("@vitals/gateway/Lan") {}

const MAX_PENDING = 3;
const PROMPTS_PER_MINUTE = 6;
const IDLE_TIMEOUT_SECONDS = 150;
const DROP_IDLE_TIMEOUT_SECONDS = 120;
const RECHECK_BLOCKED = "10 seconds";
const RECHECK_OPEN = "60 seconds";

const decodeOpen = Schema.decodeUnknownOption(Schema.fromJsonString(LanOpen));

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const prologue = encoder.encode(LAN_PROLOGUE);
const noAd = new Uint8Array(0);

const loadKey = (dataDir: string): KeyPair => {
  const path = join(dataDir, "lan.key");
  if (existsSync(path)) return keyPairFromSecret(new Uint8Array(readFileSync(path)));
  const secret = crypto.getRandomValues(new Uint8Array(32));
  writeFileSync(path, secret, { mode: 0o600 });
  chmodSync(path, 0o600);
  return keyPairFromSecret(secret);
};

const lanEndpoints = (port: number): ReadonlyArray<LanEndpoint> =>
  Object.entries(networkInterfaces())
    .filter(([name]) => name.startsWith("en"))
    .flatMap(([, entries]) => entries ?? [])
    .filter((entry) => entry.family === "IPv4" && !entry.internal && !entry.address.startsWith("169.254."))
    .map((entry) => ({ host: entry.address, port }));

type Phase =
  | { readonly _tag: "Handshake" }
  | { readonly _tag: "Waiting"; readonly promptId: string }
  | { readonly _tag: "Proxying"; readonly transport: Transport; readonly loopback: WebSocket; readonly queue: Array<string> }
  | { readonly _tag: "Closed" };

interface Conn {
  readonly address: string;
  phase: Phase;
}

interface Prompt {
  readonly socket: ServerWebSocket<Conn>;
  readonly transport: Transport;
  readonly device: DeviceInfo;
  readonly lanKey: string;
  readonly timer: ReturnType<typeof setTimeout>;
}

const sendSealed = (socket: ServerWebSocket<Conn>, transport: Transport, value: unknown) => {
  socket.send(transport.send.encrypt(noAd, encoder.encode(JSON.stringify(value))));
};

const toBytes = (message: string | Buffer): Uint8Array | null => (typeof message === "string" ? null : new Uint8Array(message));

export const layer = Layer.effect(
  Lan,
  Effect.gen(function* () {
    const config = yield* GatewayConfig;
    const auth = yield* Auth;
    const store = yield* Store;
    const bridge = yield* Bridge;
    const activity = yield* ActivityLog;
    const drops = yield* DropStore;
    const port = config.lanPort;
    const reachability = yield* SubscriptionRef.make(false);
    const off = {
      info: null,
      reachable: Effect.succeed(false),
      reachableChanges: Stream.empty,
      endpoints: () => [],
      routes: () => null,
      resolvePrompt: () => false,
    };
    if (port === null) return Lan.of(off);
    const macKey = loadKey(config.dataDir);
    const key = toBase64Url(macKey.publicKey);
    const prompts = new Map<string, Prompt>();
    const recent: Array<number> = [];

    const log = (level: "info" | "warn", kind: string, data: Record<string, unknown>, deviceId: string | null = null) =>
      activity.record({ at: Date.now(), source: "gateway", level, kind, deviceId, data });

    const tell = (message: Parameters<typeof bridge.send>[0]) => {
      Effect.runFork(bridge.send(message));
    };

    const advert = (): Promise<LanAdvert> =>
      Effect.runPromise(
        bridge.identity.pipe(
          Effect.map((identity) => identity.mac.name),
          Effect.orElseSucceed(() => "Mac"),
          Effect.map((name) => ({ protocol: PROTOCOL_VERSION, name, key, channel: config.channel })),
        ),
      );

    const endpoints = () => lanEndpoints(port);

    let tls: LanTls | null = null;

    const routes = (tailnet: string | null): MacRoutes => ({
      key,
      lan: endpoints(),
      tailnet,
      owner: auth.ownerLogin(),
      ...(tls === null ? {} : { tls }),
    });

    const endPrompt = (id: string, result: LanPairResult | null) => {
      const prompt = prompts.get(id);
      if (prompt === undefined) return false;
      prompts.delete(id);
      clearTimeout(prompt.timer);
      tell({ t: "pairPromptEnded", id });
      if (result !== null && prompt.socket.data.phase._tag === "Waiting") {
        sendSealed(prompt.socket, prompt.transport, result);
        prompt.socket.data.phase = { _tag: "Closed" };
        prompt.socket.close(1000, result.t);
      }
      return true;
    };

    const resolvePrompt = (id: string, allow: boolean) => {
      const prompt = prompts.get(id);
      if (prompt === undefined) return false;
      if (!allow) {
        log("info", "pairing.lan.denied", { device: prompt.device.name });
        return endPrompt(id, { t: "denied" });
      }
      const created = auth.pairLan(prompt.device, prompt.lanKey);
      return endPrompt(id, {
        t: "paired",
        deviceId: created.deviceId,
        token: created.token,
        scopes: pairedScopes(prompt.device.platform),
        expiresAt: created.expiresAt,
        routes: routes(null),
      });
    };

    const accept = (socket: ServerWebSocket<Conn>, answer: (accept: LanAccept) => Transport, reply: LanAccept) => {
      answer(reply);
      socket.data.phase = { _tag: "Closed" };
      socket.close(1000, reply.t);
    };

    const startProxy = (socket: ServerWebSocket<Conn>, transport: Transport, ticket: string, client: string, ready: () => void) => {
      const url = `ws://127.0.0.1:${config.port}/ws?v=${PROTOCOL_VERSION}&ticket=${encodeURIComponent(ticket)}&client=${encodeURIComponent(client)}`;
      const loopback = new WebSocket(url, { headers: { [LOOPBACK_HEADER]: auth.loopbackSecret } });
      const queue: Array<string> = [];
      socket.data.phase = { _tag: "Proxying", transport, loopback, queue };
      loopback.addEventListener("open", () => {
        ready();
        for (const text of queue.splice(0)) loopback.send(text);
      });
      loopback.addEventListener("message", (event) => {
        if (typeof event.data === "string") socket.send(transport.send.encrypt(noAd, encoder.encode(event.data)));
      });
      loopback.addEventListener("close", () => {
        socket.data.phase = { _tag: "Closed" };
        socket.close(1000, "closed");
      });
    };

    const handshake = (socket: ServerWebSocket<Conn>, bytes: Uint8Array) => {
      const noise = responder({ localStatic: macKey, prologue });
      const first = noise.readMessage1(bytes);
      const lanKey = toBase64Url(first.remoteStatic);
      const answer = (reply: LanAccept) => {
        const { message, transport } = noise.writeMessage2(encoder.encode(JSON.stringify(reply)));
        socket.send(message);
        return transport;
      };
      const open = decodeOpen(decoder.decode(first.payload));
      if (open._tag === "None") return accept(socket, answer, { t: "incompatible", protocol: PROTOCOL_VERSION });
      if (open.value.v !== PROTOCOL_VERSION) return accept(socket, answer, { t: "incompatible", protocol: PROTOCOL_VERSION });
      if (open.value.t === "connect") {
        const device = store.lanDevice(lanKey);
        const ticket = device === null ? null : auth.issueDeviceTicket(device.id);
        if (device === null || ticket === null) return accept(socket, answer, { t: "unknown" });
        const transport = noise.writeMessage2(encoder.encode(JSON.stringify({ t: "ready" } satisfies LanAccept)));
        return startProxy(socket, transport.transport, ticket, open.value.client, () => socket.send(transport.message));
      }
      const now = Date.now();
      while (recent.length > 0 && (recent[0] ?? now) < now - 60_000) recent.shift();
      if (prompts.size >= MAX_PENDING || recent.length >= PROMPTS_PER_MINUTE) return accept(socket, answer, { t: "busy" });
      recent.push(now);
      const expiresAt = now + PAIR_REQUEST_TTL_MS;
      const transport = answer({ t: "waiting", expiresAt });
      const id = newId();
      const timer = setTimeout(() => endPrompt(id, { t: "expired" }), PAIR_REQUEST_TTL_MS);
      prompts.set(id, { socket, transport, device: open.value.device, lanKey, timer });
      socket.data.phase = { _tag: "Waiting", promptId: id };
      log("info", "pairing.lan.prompt", { device: open.value.device.name, address: socket.data.address });
      tell({
        t: "pairPrompt",
        prompt: { id, device: open.value.device, code: matchCode(transport.handshakeHash), address: socket.data.address, expiresAt },
      });
    };

    const message = (socket: ServerWebSocket<Conn>, raw: string | Buffer) => {
      const bytes = toBytes(raw);
      const phase = socket.data.phase;
      if (bytes === null || phase._tag === "Closed" || phase._tag === "Waiting") return socket.close(4400, "unexpected frame");
      try {
        if (phase._tag === "Handshake") return handshake(socket, bytes);
        const text = decoder.decode(phase.transport.receive.decrypt(noAd, bytes));
        if (phase.loopback.readyState === WebSocket.OPEN) phase.loopback.send(text);
        else phase.queue.push(text);
      } catch {
        socket.data.phase = { _tag: "Closed" };
        socket.close(4400, "bad frame");
      }
    };

    const close = (socket: ServerWebSocket<Conn>) => {
      const phase = socket.data.phase;
      socket.data.phase = { _tag: "Closed" };
      if (phase._tag === "Proxying") phase.loopback.close();
      if (phase._tag === "Waiting") endPrompt(phase.promptId, null);
    };

    const server = yield* Effect.acquireRelease(
      Effect.sync(() => {
        try {
          return Bun.serve<Conn>({
            hostname: "0.0.0.0",
            port,
            fetch: (request, srv) => {
              const { pathname } = new URL(request.url);
              if (request.method === "GET" && pathname === "/.well-known/vitals") {
                return advert().then((body) => Response.json(body, { headers: { "cache-control": "no-store" } }));
              }
              const address = srv.requestIP(request)?.address ?? "unknown";
              if (pathname === "/lan" && srv.upgrade(request, { data: { address, phase: { _tag: "Handshake" } } })) return undefined;
              return new Response(null, { status: 404 });
            },
            // A frame Bun drops under backpressure desyncs the Noise counters, and the phone then reads every later frame as a
            // key mismatch. Closing instead lets it reconnect cleanly.
            websocket: { message, close, idleTimeout: IDLE_TIMEOUT_SECONDS, maxPayloadLength: MAX_FRAME_BYTES + 64, perMessageDeflate: false, closeOnBackpressureLimit: true },
          });
        } catch (error) {
          log("warn", "lan.listen.failed", { port, error: String(error) });
          return null;
        }
      }),
      (running) => Effect.sync(() => running?.stop(true)),
    );

    if (server === null) return Lan.of(off);
    log("info", "lan.listening", { port });

    const tlsPort = port + DROP_LAN_TLS_OFFSET;
    const secure = yield* Effect.acquireRelease(
      Effect.sync(() => {
        const identity = loadTlsIdentity(config.dataDir);
        if ("error" in identity) {
          log("warn", "drop.tls.failed", { port: tlsPort, error: identity.error });
          return null;
        }
        try {
          const listener = Bun.serve({
            hostname: "0.0.0.0",
            port: tlsPort,
            tls: { cert: identity.cert, key: identity.key },
            idleTimeout: DROP_IDLE_TIMEOUT_SECONDS,
            fetch: (request) => {
              const { pathname } = new URL(request.url);
              if (pathname === "/api/health" && request.method === "GET") {
                return Response.json({ ok: true, protocol: PROTOCOL_VERSION }, { headers: { "cache-control": "no-store" } });
              }
              if (pathname.startsWith("/api/drop/")) return drops.handle(request, "lan");
              return new Response(null, { status: 404 });
            },
          });
          return { listener, pin: identity.pin };
        } catch (error) {
          log("warn", "drop.tls.failed", { port: tlsPort, error: String(error) });
          return null;
        }
      }),
      (running) => Effect.sync(() => running?.listener.stop(true)),
    );
    if (secure !== null) {
      tls = { port: tlsPort, pin: secure.pin };
      log("info", "drop.tls.listening", { port: tlsPort });
    }

    const selfTest = Effect.promise(async () => {
      const first = endpoints()[0];
      if (first === undefined) return false;
      return fetch(`http://${first.host}:${first.port}/.well-known/vitals`, { signal: AbortSignal.timeout(1_500) })
        .then((response) => response.ok)
        .catch(() => false);
    });
    yield* selfTest.pipe(
      Effect.flatMap((ok) => SubscriptionRef.set(reachability, ok).pipe(Effect.as(ok))),
      Effect.flatMap((ok) => Effect.sleep(ok ? RECHECK_OPEN : RECHECK_BLOCKED)),
      Effect.forever,
      Effect.forkScoped,
    );

    return Lan.of({
      info: { port, key },
      reachable: SubscriptionRef.get(reachability),
      reachableChanges: SubscriptionRef.changes(reachability).pipe(Stream.changes),
      endpoints,
      routes,
      resolvePrompt,
    });
  }),
);
