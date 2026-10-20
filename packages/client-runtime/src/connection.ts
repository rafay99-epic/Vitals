import { type Hello, PROTOCOL_VERSION, VitalsRpc } from "@vitals/contracts";
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
import { type ReadableStore, Store } from "./store.ts";

export type VitalsClient = RpcClient.FromGroup<typeof VitalsRpc, RpcClientError.RpcClientError>;

export type ConnectionState =
  | { readonly _tag: "Idle" }
  | { readonly _tag: "Connecting"; readonly attempt: number }
  | { readonly _tag: "Ready"; readonly hello: Hello; readonly since: number }
  | { readonly _tag: "Backoff"; readonly attempt: number; readonly retryAt: number; readonly reason: string }
  | { readonly _tag: "Suspended" }
  | { readonly _tag: "Revoked"; readonly reason: string }
  | { readonly _tag: "Incompatible"; readonly serverProtocol: number | null };

export type WakeReason = "foreground" | "network" | "manual";

export interface ConnectionOptions {
  readonly baseUrl: string;
  readonly token: string | null;
  readonly clientVersion: string;
  readonly webSocket: Socket.WebSocketConstructor["Service"];
  readonly fetch?: typeof globalThis.fetch;
  readonly random?: () => number;
  readonly onTransition?: (from: ConnectionState, to: ConnectionState) => void;
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

const CONNECT_TIMEOUT = "15 seconds";
const PING_TIMEOUT = "15 seconds";
const PROBE_TIMEOUT = "3 seconds";

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null;

export const createConnection = (options: ConnectionOptions): Connection => {
  const base = options.baseUrl.replace(/\/$/, "");
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const random = options.random ?? Math.random;
  const state = new Store<ConnectionState>({ _tag: "Idle" });
  const session = Effect.runSync(SubscriptionRef.make<Session | null>(null));
  const signals = Effect.runSync(Queue.unbounded<Signal>());
  let suspended = false;
  let sessionCounter = 0;

  const transition = (next: ConnectionState) => {
    const previous = state.get();
    state.set(next);
    options.onTransition?.(previous, next);
  };

  const health = Effect.tryPromise(async () => {
    const response = await fetchImpl(`${base}/api/health`, { signal: AbortSignal.timeout(5_000) });
    const body: unknown = response.ok ? await response.json() : null;
    return isRecord(body) && typeof body["protocol"] === "number" ? body["protocol"] : null;
  }).pipe(Effect.orElseSucceed(() => null));

  const ticket = Effect.tryPromise({
    try: () =>
      fetchImpl(`${base}/api/ws-ticket`, {
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

  const socketUrl = (value: string) =>
    `${base.replace(/^http/, "ws")}/ws?v=${PROTOCOL_VERSION}&ticket=${encodeURIComponent(value)}&client=${encodeURIComponent(options.clientVersion)}`;

  const attempt = (scope: Scope.Closeable) =>
    Effect.gen(function* () {
      const value = yield* ticket;
      const disconnected = yield* Deferred.make<void>();
      const hooks = RpcClient.ConnectionHooks.of({
        onConnect: Effect.void,
        onDisconnect: Effect.asVoid(Deferred.succeed(disconnected, undefined)),
      });
      const protocol = Layer.effect(
        RpcClient.Protocol,
        RpcClient.makeProtocolSocket({ pingTimeout: PING_TIMEOUT, retryTransientErrors: false, retryPolicy: Schedule.recurs(0) }),
      ).pipe(
        Layer.provide(
          Layer.mergeAll(
            Socket.layerWebSocket(socketUrl(value), { openTimeout: CONNECT_TIMEOUT }).pipe(
              Layer.provide(Layer.succeed(Socket.WebSocketConstructor)(options.webSocket)),
            ),
            RpcSerialization.layerJson,
            Layer.succeed(RpcClient.ConnectionHooks, hooks),
          ),
        ),
      );
      const context = yield* Layer.buildWithScope(protocol, scope);
      const client = yield* RpcClient.make(VitalsRpc).pipe(Effect.provide(context), Scope.provide(scope));
      const hello = yield* client["server.hello"]({}).pipe(
        Effect.timeout(CONNECT_TIMEOUT),
        Effect.mapError(() => new AttemptFailed({ reason: "socket", message: "The Mac did not answer" })),
      );
      return { client, hello, disconnected };
    });

  const nextSignal = Queue.take(signals);

  const holdSession = (client: VitalsClient, disconnected: Deferred.Deferred<void>) => {
    const listen: Effect.Effect<"suspend" | "probe-failed"> = Effect.gen(function* () {
      while (true) {
        const signal = yield* nextSignal;
        if (signal._tag === "Suspend") return "suspend" as const;
        const probe = yield* client["server.hello"]({}).pipe(Effect.timeout(PROBE_TIMEOUT), Effect.exit);
        if (Exit.isFailure(probe)) return "probe-failed" as const;
      }
    });
    return Effect.raceFirst(Deferred.await(disconnected).pipe(Effect.as("disconnected" as const)), listen);
  };

  const waitForWake = Effect.gen(function* () {
    while (true) {
      const signal = yield* nextSignal;
      if (signal._tag === "Wake") return;
    }
  });

  const loop = Effect.gen(function* () {
    let failures = 0;
    while (true) {
      if (suspended) {
        transition({ _tag: "Suspended" });
        yield* waitForWake;
        continue;
      }
      transition({ _tag: "Connecting", attempt: failures + 1 });
      const protocol = yield* health;
      if (protocol !== null && protocol !== PROTOCOL_VERSION) {
        transition({ _tag: "Incompatible", serverProtocol: protocol });
        yield* waitForWake;
        continue;
      }
      const outcome = yield* Effect.acquireUseRelease(
        Scope.make(),
        (scope) =>
          Effect.gen(function* () {
            const result = yield* attempt(scope).pipe(Effect.exit);
            if (Exit.isFailure(result)) {
              const error = Cause.findErrorOption(result.cause);
              return error._tag === "Some"
                ? { kind: error.value.reason === "revoked" ? ("revoked" as const) : ("failed" as const), message: error.value.message, readyAt: null }
                : { kind: "failed" as const, message: "Connection failed", readyAt: null };
            }
            const readyAt = Date.now();
            sessionCounter += 1;
            yield* SubscriptionRef.set(session, { client: result.value.client, id: sessionCounter });
            transition({ _tag: "Ready", hello: result.value.hello, since: readyAt });
            const ended = yield* holdSession(result.value.client, result.value.disconnected);
            return ended === "suspend"
              ? { kind: "suspended" as const, message: "", readyAt }
              : {
                  kind: "failed" as const,
                  message: ended === "probe-failed" ? "The Mac stopped answering" : "Connection lost",
                  readyAt,
                };
          }),
        (scope) => Effect.andThen(SubscriptionRef.set(session, null), Scope.close(scope, Exit.void)),
      );
      if (outcome.readyAt !== null && Date.now() - outcome.readyAt > BACKOFF_RESET_AFTER_MS) failures = 0;
      if (outcome.kind === "suspended") continue;
      if (outcome.kind === "revoked") {
        transition({ _tag: "Revoked", reason: outcome.message });
        yield* waitForWake;
        continue;
      }
      const reason = outcome.message;
      const delay = retryDelayMs(failures, random());
      failures += 1;
      transition({ _tag: "Backoff", attempt: failures, retryAt: Date.now() + delay, reason });
      yield* Effect.raceFirst(Effect.sleep(delay), waitForWake);
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
    ).then((exit) =>
      Exit.isSuccess(exit) ? exit.value : { ok: false, error: new NotConnected({ message: "The connection closed before the Mac answered" }) },
    );
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
