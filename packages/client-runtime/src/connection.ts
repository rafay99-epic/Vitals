import { type Hello, type MacRoutes, PROTOCOL_VERSION, VitalsRpc } from "@vitals/contracts";
import type { KeyPair } from "@vitals/noise";
import * as Cause from "effect/Cause";
import * as Data from "effect/Data";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as Option from "effect/Option";
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
  /** Whether the Mac has accepted this phone's Wi-Fi key. Then Wi-Fi saying "unknown" with no Tailscale answer means the phone was removed. Defaults to true. */
  readonly lanEnrolled?: () => boolean;
  /** Wi-Fi does not know this phone but Tailscale still accepts its token, so the Wi-Fi key can be bound again. */
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
  readonly reason: "unreachable" | "identity" | "revoked" | "server" | "socket" | "unknown";
  readonly message: string;
}> {}

type Signal = { readonly _tag: "Wake"; readonly reason: WakeReason } | { readonly _tag: "Suspend" };

interface Session {
  readonly client: VitalsClient;
  readonly id: number;
  readonly calls: SubscriptionRef.SubscriptionRef<number>;
}

interface Established {
  readonly scope: Scope.Closeable;
  readonly client: VitalsClient;
  readonly hello: Hello;
  readonly disconnected: Deferred.Deferred<void>;
  readonly route: RouteKind;
  readonly latencyMs: number;
  /** Calls running on this session; a replaced session closes once it reaches 0. */
  readonly calls: SubscriptionRef.SubscriptionRef<number>;
}

interface SocketPlan {
  readonly layer: Layer.Layer<Socket.Socket>;
  /** Why the Mac turned the Wi-Fi handshake down, once it has. */
  readonly rejected: () => string | null;
}

type Ended =
  | { readonly _tag: "Suspended" }
  | { readonly _tag: "Lost"; readonly message: string }
  | { readonly _tag: "Upgrade"; readonly next: Established };

const CONNECT_TIMEOUT = "15 seconds";
const PING_TIMEOUT = "15 seconds";
// One slow answer on cellular or a relayed Tailscale path is not a lost Mac.
const HEARTBEAT_TIMEOUT = "10 seconds";
const HEARTBEAT_MS = 15_000;
// Network changes and seeing the Mac on Wi-Fi trigger an upgrade at once; this is only the safety net.
const UPGRADE_EVERY_MS = 5 * 60_000;
const HOLD_OFF_MS = 5 * 60_000;
const LAN_PROBE_MS = 1_200;
// A cold built-in Tailscale path may need a relay before the Mac answers.
const TUNNEL_PROBE_MS = 5_000;
// A call made while the connection comes back (just after opening the app) waits this long for it.
const CALL_GRACE = "5 seconds";
// The Mac bounds its own handlers; this only catches a hung one. Long clip reads retry on NotConnected.
const CALL_TIMEOUT = "3 minutes";
// After moving to Wi-Fi the old route stays open this long for calls still running on it.
const DRAIN_TIMEOUT = "30 seconds";
const WATCH_RETRY = Schedule.min([Schedule.exponential("500 millis"), Schedule.spaced("30 seconds")]);
const WATCH_REPEAT = Schedule.spaced("2 seconds");
const UNKNOWN_ON_WIFI = "The Mac does not know this phone on Wi-Fi";

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null;

const kindOf = (route: Route): RouteKind => (route._tag === "Lan" && route.tunnel !== true ? "lan" : "tailnet");

const keyOf = (route: Route): string => (route._tag === "Lan" ? `lan:${route.host}:${route.port}` : `tailnet:${route.baseUrl}`);

const failureOf = <A>(exit: Exit.Exit<A, AttemptFailed>): AttemptFailed | null =>
  Exit.isFailure(exit) ? Option.getOrNull(Cause.findErrorOption(exit.cause)) : null;

/** Runs an app callback so a throw is logged instead of stopping the connection loop or a watch. */
const safely = (run: () => void): void => {
  try {
    run();
  } catch (error) {
    console.error("Connection callback threw", error);
  }
};

export const createConnection = (options: ConnectionOptions): Connection => {
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const random = options.random ?? Math.random;
  const state = new Store<ConnectionState>({ _tag: "Idle" });
  const session = Effect.runSync(SubscriptionRef.make<Session | null>(null));
  const signals = Effect.runSync(Queue.unbounded<Signal>());
  // Every session scope is a child, so dispose closes whatever is still open.
  const root = Scope.makeUnsafe();
  const heldOff = new Map<string, number>();
  let suspended = false;
  let disposed = false;
  let sessionCounter = 0;

  const transition = (next: ConnectionState) => {
    const previous = state.get();
    state.set(next);
    safely(() => options.onTransition?.(previous, next));
  };

  const lanUnknown = () => safely(() => options.onLanUnknown?.());

  const lanReady = (): { readonly key: string; readonly device: KeyPair } | null => {
    const key = options.macKey?.() ?? null;
    const device = options.deviceKey ?? null;
    return key === null || device === null ? null : { key, device };
  };

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
    const timeoutMs = route.tunnel === true ? TUNNEL_PROBE_MS : LAN_PROBE_MS;
    return Effect.promise(() => probeLan(route.host, route.port, lan.key, fetchImpl, timeoutMs)).pipe(
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

  const socketPlan = (route: Route): Effect.Effect<SocketPlan, AttemptFailed> => {
    if (route._tag === "Tailnet") {
      const base = route.baseUrl.replace(/\/$/, "");
      return ticket(base).pipe(
        Effect.map((value) => ({
          layer: Socket.layerWebSocket(
            `${base.replace(/^http/, "ws")}/ws?v=${PROTOCOL_VERSION}&ticket=${encodeURIComponent(value)}&client=${encodeURIComponent(options.clientVersion)}`,
            { openTimeout: CONNECT_TIMEOUT },
          ).pipe(Layer.provide(Layer.succeed(Socket.WebSocketConstructor)(options.webSocket))),
          rejected: () => null,
        })),
      );
    }
    const lan = lanReady();
    if (lan === null) return Effect.fail(new AttemptFailed({ reason: "unreachable", message: "Wi-Fi route is not set up" }));
    const macKey = macKeyBytes(lan.key);
    let rejection: string | null = null;
    const lanSocket: Socket.WebSocketConstructor["Service"] = (url) =>
      openLanSocket(url, {
        macKey,
        device: lan.device,
        client: options.clientVersion,
        raw: (raw) => options.webSocket(raw),
        onRejected: (reason) => {
          rejection = reason;
        },
      });
    return Effect.succeed({
      layer: Socket.layerWebSocket(lanSocketUrl(route.host, route.port), { openTimeout: CONNECT_TIMEOUT }).pipe(
        Layer.provide(Layer.succeed(Socket.WebSocketConstructor)(lanSocket)),
      ),
      rejected: () => rejection,
    });
  };

  const timedHello = (client: VitalsClient, via: RouteKind) =>
    Effect.gen(function* () {
      const startedAt = Date.now();
      const hello = yield* client["server.hello"]({}).pipe(
        Effect.timeout(CONNECT_TIMEOUT),
        Effect.mapError(() => new AttemptFailed({ reason: "socket", message: "The Mac did not answer" })),
      );
      const routes = hello.routes;
      if (routes !== undefined) safely(() => options.onRoutes?.(routes, via));
      return { hello, latencyMs: Date.now() - startedAt };
    });

  const attempt = (route: Route): Effect.Effect<Established, AttemptFailed> =>
    Effect.gen(function* () {
      const plan = yield* socketPlan(route);
      const scope = yield* Scope.fork(root);
      return yield* Effect.gen(function* () {
        const disconnected = yield* Deferred.make<void>();
        const hooks = RpcClient.ConnectionHooks.of({
          onConnect: Effect.void,
          onDisconnect: Effect.asVoid(Deferred.succeed(disconnected, undefined)),
        });
        const protocol = Layer.effect(
          RpcClient.Protocol,
          RpcClient.makeProtocolSocket({ pingTimeout: PING_TIMEOUT, retryTransientErrors: false, retryPolicy: Schedule.recurs(0) }),
        ).pipe(Layer.provide(Layer.mergeAll(plan.layer, RpcSerialization.layerJson, Layer.succeed(RpcClient.ConnectionHooks, hooks))));
        const context = yield* Layer.buildWithScope(protocol, scope);
        const client = yield* RpcClient.make(VitalsRpc).pipe(Effect.provide(context), Scope.provide(scope));
        const { hello, latencyMs } = yield* timedHello(client, kindOf(route));
        const calls = yield* SubscriptionRef.make(0);
        return { scope, client, hello, disconnected, route: kindOf(route), latencyMs, calls };
      }).pipe(
        Effect.catchCause((cause) =>
          plan.rejected() === "unknown" && !Cause.hasInterrupts(cause)
            ? Effect.fail(new AttemptFailed({ reason: "unknown", message: UNKNOWN_ON_WIFI }))
            : Effect.failCause(cause),
        ),
        Effect.onError(() => Scope.close(scope, Exit.void)),
      );
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
    let unknownOnWifi = false;
    // Tailscale handed out a ticket, so the token is still good even if the socket then failed.
    let tokenAccepted = false;
    for (const [index, route] of routes.entries()) {
      const result = probes[index];
      if (result === undefined) continue;
      if (result._tag === "Incompatible") return { _tag: "Incompatible", protocol: result.protocol };
      if (result._tag === "Down") {
        failures.push({ kind: kindOf(route), reason: result.reason });
        continue;
      }
      const established = yield* attempt(route).pipe(Effect.exit);
      if (Exit.isSuccess(established)) {
        if (unknownOnWifi && route._tag === "Tailnet") lanUnknown();
        return { _tag: "Ready", established: established.value };
      }
      const error = failureOf(established);
      if (error?.reason === "revoked") return { _tag: "Failed", kind: "revoked", message: error.message, failures: [] };
      if (error?.reason === "unknown") {
        unknownOnWifi = true;
        failures.push({ kind: kindOf(route), reason: error.message });
        continue;
      }
      if (route._tag === "Tailnet" && error?.reason === "socket") tokenAccepted = true;
      heldOff.set(keyOf(route), Date.now() + HOLD_OFF_MS);
      failures.push({ kind: kindOf(route), reason: error?.message ?? "Connection failed" });
    }
    if (unknownOnWifi && tokenAccepted) lanUnknown();
    // Wi-Fi forgot a key it had accepted and nothing else vouches for the token: this phone was removed.
    if (unknownOnWifi && !tokenAccepted && options.lanEnrolled?.() !== false) {
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
      const next = yield* attempt(target).pipe(Effect.exit);
      if (Exit.isSuccess(next)) return next.value;
      // The current Tailscale session can bind the Wi-Fi key again.
      if (failureOf(next)?.reason === "unknown") lanUnknown();
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
        // A burst of wakes asks for one check, not one each.
        if (signal._tag === "Some") yield* Queue.clear(signals);
        if (suspended) return { _tag: "Suspended" } satisfies Ended;
        const startedAt = Date.now();
        const beat = yield* established.client["server.hello"]({}).pipe(Effect.timeout(HEARTBEAT_TIMEOUT), Effect.exit);
        if (Exit.isFailure(beat)) return { _tag: "Lost", message: "The Mac stopped answering" } satisfies Ended;
        const routes = beat.value.routes;
        if (routes !== undefined) safely(() => options.onRoutes?.(routes, established.route));
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

  /** Waits for the next wake; suspends that arrive meanwhile are already reflected in `suspended`. */
  const waitForWake: Effect.Effect<WakeReason> = Effect.gen(function* () {
    while (true) {
      const signal = yield* Queue.take(signals);
      if (signal._tag === "Wake") return signal.reason;
    }
  });

  const adopt = (established: Established) =>
    Effect.gen(function* () {
      sessionCounter += 1;
      yield* SubscriptionRef.set(session, { client: established.client, id: sessionCounter, calls: established.calls });
      transition({
        _tag: "Ready",
        hello: established.hello,
        since: Date.now(),
        route: established.route,
        latencyMs: established.latencyMs,
      });
    });

  const close = (established: Established) => Scope.close(established.scope, Exit.void);

  /** Closes a replaced session once its last call has answered, or after DRAIN_TIMEOUT. */
  const retire = (established: Established) =>
    SubscriptionRef.changes(established.calls).pipe(
      Stream.filter((count) => count === 0),
      Stream.runHead,
      Effect.timeoutOption(DRAIN_TIMEOUT),
      Effect.andThen(close(established)),
      Effect.forkIn(root),
      Effect.asVoid,
    );

  /**
   * Shows Backoff and waits out the delay for the current failure count, or until a wake.
   * Returns the next failure count: a foreground or manual wake starts the count over.
   */
  const backoff = (failures: number, reason: string, routes: ReadonlyArray<RouteFailure>): Effect.Effect<number> =>
    Effect.gen(function* () {
      const delay = retryDelayMs(failures, random());
      // Wakes queued while connecting are already answered by this attempt.
      yield* Queue.clear(signals);
      transition({ _tag: "Backoff", attempt: failures + 1, retryAt: Date.now() + delay, reason, failures: routes });
      const woke = yield* Effect.raceFirst(Effect.as(Effect.sleep(delay), null), Queue.take(signals));
      return woke?._tag === "Wake" && woke.reason !== "network" ? 0 : failures + 1;
    });

  const loop = Effect.gen(function* () {
    let failures = 0;
    // A session an upgrade already adopted; it is held next.
    let upgraded: Established | null = null;
    while (true) {
      if (suspended) {
        if (upgraded !== null) {
          // The suspend landed while moving to Wi-Fi: the new session must not stay open in the background.
          yield* SubscriptionRef.set(session, null);
          yield* close(upgraded);
          upgraded = null;
        }
        yield* Queue.clear(signals);
        if (!suspended) continue;
        transition({ _tag: "Suspended" });
        // Only the app coming back resumes; a network wake leaves the connection suspended.
        let reason = yield* waitForWake;
        while (reason === "network") reason = yield* waitForWake;
        failures = 0;
        continue;
      }
      let established: Established | null = upgraded;
      upgraded = null;
      if (established === null) {
        transition({ _tag: "Connecting", attempt: failures + 1 });
        const result = yield* connect;
        if (result._tag === "Failed" && result.kind === "failed") {
          failures = yield* backoff(failures, result.message, result.failures);
          continue;
        }
        if (result._tag !== "Ready") {
          yield* Queue.clear(signals);
          transition(result._tag === "Incompatible" ? { _tag: "Incompatible", serverProtocol: result.protocol } : { _tag: "Revoked", reason: result.message });
          yield* waitForWake;
          continue;
        }
        established = result.established;
        yield* adopt(established);
      }
      const current: Established = established;
      const readyAt = Date.now();
      const ended: Ended = yield* holdSession(current).pipe(
        Effect.onError(() => Effect.andThen(SubscriptionRef.set(session, null), close(current))),
      );
      const lasted = Date.now() - readyAt >= BACKOFF_RESET_AFTER_MS;
      if (lasted) failures = 0;
      if (ended._tag === "Upgrade") {
        yield* adopt(ended.next);
        yield* retire(current);
        upgraded = ended.next;
        continue;
      }
      yield* SubscriptionRef.set(session, null);
      yield* close(current);
      // A session that dies soon after connecting counts as a failed attempt, or a flaky route reconnects in a tight loop.
      if (ended._tag === "Lost" && !lasted) failures = yield* backoff(failures, ended.message, [{ kind: current.route, reason: ended.message }]);
    }
  });

  const main = Effect.runFork(
    Effect.forever(
      loop.pipe(
        Effect.catchDefect((defect) =>
          Effect.andThen(
            Effect.sync(() => console.error("Connection loop failed, restarting", defect)),
            Effect.sleep("1 second"),
          ),
        ),
      ),
    ),
  );

  /** The live session, waiting briefly while the connection is on its way back. */
  const sessionSoon: Effect.Effect<Session | null> = Effect.suspend(() => {
    const tag = state.get()._tag;
    if (disposed || tag === "Revoked" || tag === "Incompatible") return SubscriptionRef.get(session);
    return SubscriptionRef.changes(session).pipe(
      Stream.filter((current) => current !== null),
      Stream.runHead,
      Effect.timeoutOption(CALL_GRACE),
      Effect.map((found) => Option.getOrNull(Option.flatten(found))),
    );
  });

  const call = <A, E>(run: (client: VitalsClient) => Effect.Effect<A, E>): Promise<CallResult<A, E>> => {
    const program: Effect.Effect<A, E | NotConnected> = Effect.flatMap(sessionSoon, (current): Effect.Effect<A, E | NotConnected> => {
      if (current === null) return Effect.fail(new NotConnected({ message: "Not connected to your Mac" }));
      return SubscriptionRef.update(current.calls, (count) => count + 1).pipe(
        Effect.andThen(run(current.client)),
        Effect.timeoutOrElse({
          duration: CALL_TIMEOUT,
          orElse: () => Effect.fail(new NotConnected({ message: "The Mac took too long to answer" })),
        }),
        Effect.ensuring(SubscriptionRef.update(current.calls, (count) => count - 1)),
      );
    });
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

  /** Follows `open` on every session; a stream that fails or ends while the session lives is opened again. */
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
                Stream.tapError((error) => Effect.sync(() => safely(() => onError?.(error)))),
                Stream.retry(WATCH_RETRY),
                Stream.repeat(WATCH_REPEAT),
                Stream.catchCause((cause) => {
                  if (!Cause.hasInterruptsOnly(cause)) safely(() => onError?.(Cause.squash(cause)));
                  return Stream.empty;
                }),
              ),
        ),
        Stream.runForEach((value) => Effect.sync(() => safely(() => onValue(value)))),
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
      // A network change in the background is no reason to reconnect; only the app coming back is.
      if (reason !== "network") suspended = false;
      Effect.runSync(Queue.offer(signals, { _tag: "Wake", reason }));
    },
    suspend: () => {
      suspended = true;
      Effect.runSync(Queue.offer(signals, { _tag: "Suspend" }));
    },
    dispose: () => {
      if (disposed) return;
      disposed = true;
      Effect.runFork(
        Fiber.interrupt(main).pipe(
          Effect.andThen(SubscriptionRef.set(session, null)),
          Effect.andThen(Scope.close(root, Exit.void)),
        ),
      );
    },
  };
};
