import { type Hello, type MacRoutes, PROTOCOL_VERSION, VitalsRpc } from "@vitals/contracts";
import type { KeyPair } from "@vitals/noise";
import * as Cause from "effect/Cause";
import * as Data from "effect/Data";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";
import * as Schedule from "effect/Schedule";
import * as Scope from "effect/Scope";
import * as Stream from "effect/Stream";
import * as SubscriptionRef from "effect/SubscriptionRef";
import * as RpcClient from "effect/rpc/RpcClient";
import type * as RpcClientError from "effect/rpc/RpcClientError";
import * as RpcSerialization from "effect/rpc/RpcSerialization";
import * as Socket from "effect/socket/Socket";

import { authHeaders } from "./account.ts";
import { BACKOFF_RESET_AFTER_MS, retryDelayMs } from "./backoff.ts";
import { lanSocketUrl, macKeyBytes, openLanSocket, probeLan } from "./lan.ts";
import { type ReadableStore, Store } from "./store.ts";

export type VitalsClient = RpcClient.FromGroup<typeof VitalsRpc, RpcClientError.RpcClientError>;

export type RouteKind = "lan" | "tailnet";

export type Route =
  | { readonly _tag: "Lan"; readonly host: string; readonly port: number; readonly tunnel?: boolean }
  | { readonly _tag: "Tailnet"; readonly baseUrl: string };

export interface RouteFailure {
  readonly kind: RouteKind;
  readonly reason: string;
}

export type ConnectionState =
  | { readonly _tag: "Idle" }
  | { readonly _tag: "Connecting"; readonly attempt: number }
  | { readonly _tag: "Ready"; readonly hello: Hello; readonly since: number; readonly route: RouteKind; readonly latencyMs: number | null }
  | {
      readonly _tag: "Backoff";
      readonly attempt: number;
      readonly retryAt: number;
      readonly reason: string;
      readonly failures: ReadonlyArray<RouteFailure>;
    }
  | { readonly _tag: "Suspended" }
  | { readonly _tag: "Revoked"; readonly reason: string }
  | { readonly _tag: "Incompatible"; readonly serverProtocol: number | null };

export type WakeReason = "foreground" | "network" | "manual";

export interface ConnectionOptions {
  readonly routes: () => ReadonlyArray<Route>;
  readonly token: string | null;
  readonly macKey?: () => string | null;
  readonly deviceKey?: KeyPair | null;
  readonly clientVersion: string;
  readonly webSocket: Socket.WebSocketConstructor["Service"];
  readonly fetch?: typeof globalThis.fetch;
  readonly random?: () => number;
  readonly onTransition?: (from: ConnectionState, to: ConnectionState) => void;
  readonly onRoutes?: (routes: MacRoutes, via: RouteKind) => void;
  readonly lanEnrolled?: () => boolean;
  readonly onLanUnknown?: () => void;
}

export type CallResult<A, E> =
  | { readonly ok: true; readonly value: A }
  | { readonly ok: false; readonly error: E | NotConnected };

export interface Connection {
  readonly state: ReadableStore<ConnectionState>;
  readonly call: <A, E>(run: (client: VitalsClient) => Effect.Effect<A, E>) => Promise<CallResult<A, E>>;
  readonly watch: <A, E>(
    open: (client: VitalsClient) => Stream.Stream<A, E>,
    onValue: (value: A) => void,
    onError?: (error: unknown) => void,
  ) => () => void;
  readonly wake: (reason: WakeReason) => void;
  readonly suspend: () => void;
  readonly dispose: () => void;
}

export class NotConnected extends Data.TaggedError("NotConnected")<{ readonly message: string }> {}

class AttemptFailed extends Data.TaggedError("AttemptFailed")<{
  readonly reason: "unreachable" | "identity" | "revoked" | "server" | "socket";
  readonly message: string;
}> {}

type Signal = { readonly _tag: "Wake"; readonly reason: WakeReason } | { readonly _tag: "Suspend" };

interface Session {
  readonly client: VitalsClient;
  readonly id: number;
}

interface Established {
  readonly scope: Scope.Closeable;
  readonly client: VitalsClient;
  readonly hello: Hello;
  readonly disconnected: Deferred.Deferred<void>;
  readonly route: RouteKind;
  readonly latencyMs: number;
}

type Ended =
  | { readonly _tag: "Suspended" }
  | { readonly _tag: "Lost"; readonly message: string }
  | { readonly _tag: "Upgrade"; readonly next: Established };

const CONNECT_TIMEOUT = "15 seconds";
const PING_TIMEOUT = "15 seconds";
const PROBE_TIMEOUT = "3 seconds";
const HEARTBEAT_MS = 15_000;
const UPGRADE_EVERY_MS = 60_000;
const HOLD_OFF_MS = 5 * 60_000;
const LAN_PROBE_MS = 1_200;

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null;

const kindOf = (route: Route): RouteKind => (route._tag === "Lan" && route.tunnel !== true ? "lan" : "tailnet");

const keyOf = (route: Route): string => (route._tag === "Lan" ? `lan:${route.host}:${route.port}` : `tailnet:${route.baseUrl}`);

export const createConnection = (options: ConnectionOptions): Connection => {
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const random = options.random ?? Math.random;
  const state = new Store<ConnectionState>({ _tag: "Idle" });
  const session = Effect.runSync(SubscriptionRef.make<Session | null>(null));
  const signals = Effect.runSync(Queue.unbounded<Signal>());
  const heldOff = new Map<string, number>();
  let suspended = false;
  let sessionCounter = 0;

  const transition = (next: ConnectionState) => {
    const previous = state.get();
    state.set(next);
    options.onTransition?.(previous, next);
  };

  const lanReady = (): { readonly key: string; readonly device: KeyPair } | null => {
    const key = options.macKey?.() ?? null;
    const device = options.deviceKey ?? null;
    if (key === null || device === null || options.lanEnrolled?.() === false) return null;
    return { key, device };
  };

  let lanRejectedAsUnknown = false;

  const health = (baseUrl: string) =>
    Effect.tryPromise(async () => {
      const response = await fetchImpl(`${baseUrl}/api/health`, { signal: AbortSignal.timeout(2_500) });
      const body: unknown = response.ok ? await response.json() : null;
      return isRecord(body) && typeof body["protocol"] === "number" ? body["protocol"] : null;
    }).pipe(Effect.orElseSucceed(() => null));

  type Probe = { readonly _tag: "Ok" } | { readonly _tag: "Down"; readonly reason: string } | { readonly _tag: "Incompatible"; readonly protocol: number };

  const probe = (route: Route): Effect.Effect<Probe> => {
    if (route._tag === "Tailnet") {
      return health(route.baseUrl.replace(/\/$/, "")).pipe(
        Effect.map((protocol): Probe => {
          if (protocol === null) return { _tag: "Down", reason: "Tailscale route did not answer" };
          return protocol === PROTOCOL_VERSION ? { _tag: "Ok" } : { _tag: "Incompatible", protocol };
        }),
      );
    }
    const lan = lanReady();
    if (lan === null) return Effect.succeed({ _tag: "Down", reason: "Wi-Fi route is not set up" });
    return Effect.promise(() => probeLan(route.host, route.port, lan.key, fetchImpl, LAN_PROBE_MS)).pipe(
      Effect.map((advert): Probe => {
        if (advert === null) return { _tag: "Down", reason: route.tunnel === true ? "Built-in Tailscale could not reach the Mac" : "Not on the Mac's Wi-Fi" };
        return advert.protocol === PROTOCOL_VERSION ? { _tag: "Ok" } : { _tag: "Incompatible", protocol: advert.protocol };
      }),
    );
  };

  const ticket = (baseUrl: string) =>
    Effect.tryPromise({
      try: () =>
        fetchImpl(`${baseUrl}/api/ws-ticket`, {
          method: "POST",
          headers: authHeaders(options.token),
          signal: AbortSignal.timeout(10_000),
        }),
      catch: () => new AttemptFailed({ reason: "unreachable", message: "Mac is unreachable" }),
    }).pipe(
      Effect.flatMap((response) => {
        if (response.status === 401) return Effect.fail(new AttemptFailed({ reason: "revoked", message: "This device is no longer paired" }));
        if (response.status === 403) return Effect.fail(new AttemptFailed({ reason: "identity", message: "Tailnet identity was rejected" }));
        if (!response.ok) return Effect.fail(new AttemptFailed({ reason: "server", message: `Gateway answered ${response.status}` }));
        return Effect.tryPromise({
          try: async (): Promise<unknown> => response.json(),
          catch: () => new AttemptFailed({ reason: "server", message: "Gateway sent an invalid ticket" }),
        });
      }),
      Effect.flatMap((body) =>
        isRecord(body) && typeof body["ticket"] === "string"
          ? Effect.succeed(body["ticket"])
          : Effect.fail(new AttemptFailed({ reason: "server", message: "Gateway sent an invalid ticket" })),
      ),
    );

  const socketLayer = (route: Route): Effect.Effect<Layer.Layer<Socket.Socket>, AttemptFailed> => {
    if (route._tag === "Tailnet") {
      const base = route.baseUrl.replace(/\/$/, "");
      return ticket(base).pipe(
        Effect.map((value) =>
          Socket.layerWebSocket(
            `${base.replace(/^http/, "ws")}/ws?v=${PROTOCOL_VERSION}&ticket=${encodeURIComponent(value)}&client=${encodeURIComponent(options.clientVersion)}`,
            { openTimeout: CONNECT_TIMEOUT },
          ).pipe(Layer.provide(Layer.succeed(Socket.WebSocketConstructor)(options.webSocket))),
        ),
      );
    }
    const lan = lanReady();
    if (lan === null) return Effect.fail(new AttemptFailed({ reason: "unreachable", message: "Wi-Fi route is not set up" }));
    const macKey = macKeyBytes(lan.key);
    const lanSocket: Socket.WebSocketConstructor["Service"] = (url) =>
      openLanSocket(url, {
        macKey,
        device: lan.device,
        client: options.clientVersion,
        raw: (raw) => options.webSocket(raw),
        onRejected: (reason) => {
          lanRejectedAsUnknown = reason === "unknown";
        },
      });
    return Effect.succeed(
      Socket.layerWebSocket(lanSocketUrl(route.host, route.port), { openTimeout: CONNECT_TIMEOUT }).pipe(
        Layer.provide(Layer.succeed(Socket.WebSocketConstructor)(lanSocket)),
      ),
    );
  };

  const timedHello = (client: VitalsClient, via: RouteKind) =>
    Effect.gen(function* () {
      const startedAt = Date.now();
      const hello = yield* client["server.hello"]({}).pipe(
        Effect.timeout(CONNECT_TIMEOUT),
        Effect.mapError(() => new AttemptFailed({ reason: "socket", message: "The Mac did not answer" })),
      );
      if (hello.routes !== undefined) options.onRoutes?.(hello.routes, via);
      return { hello, latencyMs: Date.now() - startedAt };
    });

  const attempt = (route: Route): Effect.Effect<Established, AttemptFailed> =>
    Effect.gen(function* () {
      const scope = yield* Scope.make();
      const built = yield* Effect.gen(function* () {
        const socket = yield* socketLayer(route);
        const disconnected = yield* Deferred.make<void>();
        const hooks = RpcClient.ConnectionHooks.of({
          onConnect: Effect.void,
          onDisconnect: Effect.asVoid(Deferred.succeed(disconnected, undefined)),
        });
        const protocol = Layer.effect(
          RpcClient.Protocol,
          RpcClient.makeProtocolSocket({ pingTimeout: PING_TIMEOUT, retryTransientErrors: false, retryPolicy: Schedule.recurs(0) }),
        ).pipe(Layer.provide(Layer.mergeAll(socket, RpcSerialization.layerJson, Layer.succeed(RpcClient.ConnectionHooks, hooks))));
        const context = yield* Layer.buildWithScope(protocol, scope);
        const client = yield* RpcClient.make(VitalsRpc).pipe(Effect.provide(context), Scope.provide(scope));
        const { hello, latencyMs } = yield* timedHello(client, kindOf(route));
        return { scope, client, hello, disconnected, route: kindOf(route), latencyMs };
      }).pipe(Effect.onError(() => Scope.close(scope, Exit.void)));
      return built;
    });

  type Connect =
    | { readonly _tag: "Ready"; readonly established: Established }
    | { readonly _tag: "Failed"; readonly kind: "revoked" | "failed"; readonly message: string; readonly failures: ReadonlyArray<RouteFailure> }
    | { readonly _tag: "Incompatible"; readonly protocol: number };

  const connect: Effect.Effect<Connect> = Effect.gen(function* () {
    const routes = options.routes();
    if (routes.length === 0) return { _tag: "Failed", kind: "failed", message: "No route to the Mac", failures: [] };
    const probes = yield* Effect.forEach(routes, probe, { concurrency: "unbounded" });
    const failures: Array<RouteFailure> = [];
    let unknownOnLan = false;
    for (const [index, route] of routes.entries()) {
      const result = probes[index];
      if (result === undefined) continue;
      if (result._tag === "Incompatible") return { _tag: "Incompatible", protocol: result.protocol };
      if (result._tag === "Down") {
        failures.push({ kind: kindOf(route), reason: result.reason });
        continue;
      }
      lanRejectedAsUnknown = false;
      const established = yield* attempt(route).pipe(Effect.exit);
      if (Exit.isSuccess(established)) return { _tag: "Ready", established: established.value };
      const error = Cause.findErrorOption(established.cause);
      const reason = error._tag === "Some" ? error.value : null;
      if (reason?.reason === "revoked") return { _tag: "Failed", kind: "revoked", message: reason.message, failures: [] };
      if (route._tag === "Lan" && lanRejectedAsUnknown) {
        unknownOnLan = true;
        options.onLanUnknown?.();
        failures.push({ kind: "lan", reason: "The Mac does not know this phone on Wi-Fi" });
        continue;
      }
      heldOff.set(keyOf(route), Date.now() + HOLD_OFF_MS);
      failures.push({ kind: kindOf(route), reason: reason?.message ?? "Connection failed" });
    }
    if (unknownOnLan && routes.every((route) => route._tag === "Lan")) {
      return { _tag: "Failed", kind: "revoked", message: "This device is no longer paired", failures: [] };
    }
    return { _tag: "Failed", kind: "failed", message: failures[0]?.reason ?? "Mac is unreachable", failures };
  });

  const upgradeTarget = (current: RouteKind): Route | null => {
    if (current === "lan") return null;
    const now = Date.now();
    return options.routes().find((route) => route._tag === "Lan" && route.tunnel !== true && (heldOff.get(keyOf(route)) ?? 0) < now) ?? null;
  };

  const tryUpgrade = (current: RouteKind): Effect.Effect<Established | null> =>
    Effect.gen(function* () {
      const target = upgradeTarget(current);
      if (target === null) return null;
      const reachable = yield* probe(target);
      if (reachable._tag !== "Ok") return null;
      lanRejectedAsUnknown = false;
      const next = yield* attempt(target).pipe(Effect.exit);
      if (Exit.isSuccess(next)) return next.value;
      if (lanRejectedAsUnknown) options.onLanUnknown?.();
      heldOff.set(keyOf(target), Date.now() + HOLD_OFF_MS);
      return null;
    });

  const holdSession = (established: Established): Effect.Effect<Ended> => {
    let latencyMs = established.latencyMs;
    let lastUpgradeAt = Date.now();
    const ready = () =>
      transition({ _tag: "Ready", hello: established.hello, since: Date.now(), route: established.route, latencyMs });
    const listen = Effect.gen(function* () {
      while (true) {
        const signal = yield* Queue.take(signals).pipe(Effect.timeoutOption(HEARTBEAT_MS));
        if (signal._tag === "Some" && signal.value._tag === "Suspend") return { _tag: "Suspended" } satisfies Ended;
        const startedAt = Date.now();
        const beat = yield* established.client["server.hello"]({}).pipe(Effect.timeout(PROBE_TIMEOUT), Effect.exit);
        if (Exit.isFailure(beat)) return { _tag: "Lost", message: "The Mac stopped answering" } satisfies Ended;
        if (beat.value.routes !== undefined) options.onRoutes?.(beat.value.routes, established.route);
        latencyMs = Date.now() - startedAt;
        ready();
        const due = signal._tag === "Some" || Date.now() - lastUpgradeAt >= UPGRADE_EVERY_MS;
        if (!due) continue;
        lastUpgradeAt = Date.now();
        const next = yield* tryUpgrade(established.route);
        if (next !== null) return { _tag: "Upgrade", next } satisfies Ended;
      }
    });
    const lost = Deferred.await(established.disconnected).pipe(Effect.as({ _tag: "Lost", message: "Connection lost" } satisfies Ended));
    return Effect.raceFirst(lost, listen);
  };

  const waitForWake = Effect.gen(function* () {
    while (true) {
      const signal = yield* Queue.take(signals);
      if (signal._tag === "Wake") return;
    }
  });

  const adopt = (established: Established) =>
    Effect.gen(function* () {
      sessionCounter += 1;
      yield* SubscriptionRef.set(session, { client: established.client, id: sessionCounter });
      transition({
        _tag: "Ready",
        hello: established.hello,
        since: Date.now(),
        route: established.route,
        latencyMs: established.latencyMs,
      });
    });

  const loop = Effect.gen(function* () {
    let failures = 0;
    let pending: Established | null = null;
    let adopted = false;
    while (true) {
      if (suspended) {
        transition({ _tag: "Suspended" });
        yield* waitForWake;
        continue;
      }
      let established: Established | null = pending;
      pending = null;
      if (established === null) {
        transition({ _tag: "Connecting", attempt: failures + 1 });
        const result = yield* connect;
        if (result._tag === "Incompatible") {
          transition({ _tag: "Incompatible", serverProtocol: result.protocol });
          yield* waitForWake;
          continue;
        }
        if (result._tag === "Failed" && result.kind === "revoked") {
          transition({ _tag: "Revoked", reason: result.message });
          yield* waitForWake;
          continue;
        }
        if (result._tag === "Failed") {
          const delay = retryDelayMs(failures, random());
          failures += 1;
          transition({ _tag: "Backoff", attempt: failures, retryAt: Date.now() + delay, reason: result.message, failures: result.failures });
          yield* Effect.raceFirst(Effect.sleep(delay), waitForWake);
          continue;
        }
        established = result.established;
      }
      const readyAt = Date.now();
      if (!adopted) yield* adopt(established);
      adopted = false;
      const ended: Ended = yield* holdSession(established);
      if (ended._tag === "Upgrade") {
        yield* adopt(ended.next);
        pending = ended.next;
        adopted = true;
      } else {
        yield* SubscriptionRef.set(session, null);
      }
      yield* Scope.close(established.scope, Exit.void);
      if (Date.now() - readyAt > BACKOFF_RESET_AFTER_MS) failures = 0;
    }
  });

  const main = Effect.runFork(loop);

  const call = <A, E>(run: (client: VitalsClient) => Effect.Effect<A, E>): Promise<CallResult<A, E>> => {
    const program: Effect.Effect<A, E | NotConnected> = Effect.flatMap(
      SubscriptionRef.get(session),
      (current): Effect.Effect<A, E | NotConnected> =>
        current === null ? Effect.fail(new NotConnected({ message: "Not connected to your Mac" })) : run(current.client),
    );
    return Effect.runPromiseExit(
      Effect.match(program, {
        onFailure: (error): CallResult<A, E> => ({ ok: false, error }),
        onSuccess: (value): CallResult<A, E> => ({ ok: true, value }),
      }),
    ).then((exit) => {
      if (Exit.isSuccess(exit)) return exit.value;
      if (Cause.hasInterruptsOnly(exit.cause)) {
        return { ok: false, error: new NotConnected({ message: "The connection closed before the Mac answered" }) };
      }
      throw Cause.squash(exit.cause);
    });
  };

  const watch = <A, E>(
    open: (client: VitalsClient) => Stream.Stream<A, E>,
    onValue: (value: A) => void,
    onError?: (error: unknown) => void,
  ) => {
    const fiber = Effect.runFork(
      SubscriptionRef.changes(session).pipe(
        Stream.switchMap((current) =>
          current === null
            ? Stream.empty
            : open(current.client).pipe(
                Stream.catchCause((cause) => {
                  if (!Cause.hasInterruptsOnly(cause)) onError?.(Cause.squash(cause));
                  return Stream.empty;
                }),
              ),
        ),
        Stream.runForEach((value) => Effect.sync(() => onValue(value))),
      ),
    );
    return () => {
      Effect.runFork(Fiber.interrupt(fiber));
    };
  };

  return {
    state,
    call,
    watch,
    wake: (reason) => {
      suspended = false;
      Effect.runSync(Queue.offer(signals, { _tag: "Wake", reason }));
    },
    suspend: () => {
      suspended = true;
      Effect.runSync(Queue.offer(signals, { _tag: "Suspend" }));
    },
    dispose: () => {
      Effect.runFork(Fiber.interrupt(main));
    },
  };
};
