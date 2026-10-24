import { type Scope, AuthError, PROTOCOL_VERSION, RPC_SCOPES, ScopeAuthorization, VitalsRpc, requiredScope } from "@vitals/contracts";
import type { VitalsMethod } from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Option from "effect/Option";
import * as HttpRouter from "effect/http/HttpRouter";
import * as HttpServerRequest from "effect/http/HttpServerRequest";
import * as HttpServerResponse from "effect/http/HttpServerResponse";
import type * as RpcMessage from "effect/rpc/RpcMessage";
import * as RpcSerialization from "effect/rpc/RpcSerialization";
import * as RpcServer from "effect/rpc/RpcServer";

import { ActivityLog, type FrameRecord } from "../activity/ActivityLog.ts";
import { Auth, type Session } from "../auth/Auth.ts";
import { Connections } from "./Connections.ts";
import { handlersLayer } from "./handlers.ts";

const isMethod = (tag: string): tag is VitalsMethod => Object.hasOwn(RPC_SCOPES, tag);

const frameBytes = (value: unknown): number => JSON.stringify(value)?.length ?? 0;

/**
 * Clip chunk traffic: one call per 512 KB, so a big file is thousands of calls. These keep no frame or
 * rpc.call rows; ClipStore writes one `clip.download` / `clip.upload` summary per transfer instead.
 */
const BULK_METHODS: ReadonlySet<string> = new Set(["clips.read", "clips.send.chunk"]);

export const loginHeader = (request: HttpServerRequest.HttpServerRequest): string | null =>
  request.headers["tailscale-user-login"] ?? null;

export const LOOPBACK_HEADER = "x-vitals-loopback";

const scopeLayer = (session: Session, connectionId: string, record: ActivityLog["Service"]["record"]) =>
  Layer.succeed(ScopeAuthorization)((effect, { rpc, payload }) => {
    const method = rpc._tag;
    const needed: Scope = isMethod(method) ? requiredScope(method, payload) : "destructive";
    if (!session.device.scopes.includes(needed)) {
      record({
        at: Date.now(),
        source: "gateway",
        level: "warn",
        kind: "auth.scope.denied",
        deviceId: session.device.id,
        connectionId,
        rpc: method,
        data: { needed },
      });
      return Effect.fail(new AuthError({ message: `This device needs the ${needed} scope`, requiredScope: needed }));
    }
    const started = performance.now();
    return effect.pipe(
      Effect.onExit((exit) =>
        Effect.sync(() => {
          if (exit._tag === "Success" && BULK_METHODS.has(method)) return;
          record({
            at: Date.now(),
            source: "gateway",
            level: exit._tag === "Success" ? "debug" : "warn",
            kind: "rpc.call",
            deviceId: session.device.id,
            connectionId,
            rpc: method,
            durationMs: performance.now() - started,
            data: { ok: exit._tag === "Success" },
          });
        }),
      ),
    );
  });

const instrument = (
  protocol: RpcServer.Protocol["Service"],
  connectionId: string,
  activity: Pick<ActivityLog["Service"], "frame" | "tally">,
): RpcServer.Protocol["Service"] => {
  const methods = new Map<string, string>();
  const methodFor = (id: string | number) => methods.get(String(id)) ?? null;
  const frame = (record: FrameRecord) =>
    record.method !== null && BULK_METHODS.has(record.method) ? activity.tally(record) : activity.frame(record);
  return {
    ...protocol,
    run: (handle) =>
      protocol.run((clientId, data: RpcMessage.FromClientEncoded) => {
        const rpcId = data._tag === "Request" ? String(data.id) : "requestId" in data ? String(data.requestId) : null;
        if (data._tag === "Request") methods.set(String(data.id), data.tag);
        frame({
          connectionId,
          at: Date.now(),
          dir: "in",
          rpcId,
          method: rpcId === null ? null : methodFor(rpcId),
          tag: data._tag,
          bytes: frameBytes(data),
        });
        return handle(clientId, data);
      }),
    send: (clientId, response: RpcMessage.FromServerEncoded, transferables) => {
      const rpcId = "requestId" in response ? String(response.requestId) : null;
      frame({
        connectionId,
        at: Date.now(),
        dir: "out",
        rpcId,
        method: rpcId === null ? null : methodFor(rpcId),
        tag: response._tag,
        bytes: frameBytes(response),
      });
      if (response._tag === "Exit" && rpcId !== null) methods.delete(rpcId);
      return protocol.send(clientId, response, transferables);
    },
  };
};

const problem = (status: number, code: string, message: string) =>
  HttpServerResponse.jsonUnsafe({ code, message }, { status });

export const wsRoute = HttpRouter.add(
  "GET",
  "/ws",
  Effect.gen(function* () {
    const request = yield* HttpServerRequest.HttpServerRequest;
    const auth = yield* Auth;
    const activity = yield* ActivityLog;
    const connections = yield* Connections;
    const url = HttpServerRequest.toURL(request);
    if (Option.isNone(url) || url.value.searchParams.get("v") !== String(PROTOCOL_VERSION)) {
      activity.record({ at: Date.now(), source: "gateway", level: "warn", kind: "ws.upgrade.rejected", data: { status: 426 } });
      return problem(426, "protocol_incompatible", `Update the app to protocol ${PROTOCOL_VERSION}`);
    }
    const login = loginHeader(request);
    const loopback = request.headers[LOOPBACK_HEADER] === auth.loopbackSecret;
    const identity = loopback ? null : auth.checkIdentity(login);
    if (identity !== null) {
      activity.record({ at: Date.now(), source: "gateway", level: "warn", kind: "ws.upgrade.rejected", data: { status: 403 } });
      return problem(403, identity.reason, identity.message);
    }
    const session = auth.redeemTicket(url.value.searchParams.get("ticket") ?? "");
    if (session === null) {
      activity.record({ at: Date.now(), source: "gateway", level: "warn", kind: "ws.upgrade.rejected", data: { status: 401 } });
      return problem(401, "credentials", "Ticket is missing or expired");
    }
    const connectionId = newId();
    const deviceId = session.device.id;
    const clientVersion = url.value.searchParams.get("client");
    activity.connectionOpened({ id: connectionId, deviceId, openedAt: Date.now(), tsLogin: loopback ? "wifi" : login, clientVersion });
    activity.record({ at: Date.now(), source: "gateway", level: "info", kind: "ws.opened", deviceId, connectionId, data: { clientVersion } });

    const served = Effect.gen(function* () {
      const { protocol, httpEffect } = yield* RpcServer.makeProtocolWithHttpEffectWebsocket;
      yield* RpcServer.make(VitalsRpc, { disableTracing: true, disableFatalDefects: true }).pipe(
        Effect.provideService(RpcServer.Protocol, instrument(protocol, connectionId, activity)),
        Effect.provide(Layer.merge(handlersLayer(session, connectionId), scopeLayer(session, connectionId, activity.record))),
        Effect.forkScoped,
      );
      return httpEffect;
    }).pipe(Effect.provide(RpcSerialization.layerJson));

    const handler = yield* served;
    return yield* Effect.acquireUseRelease(
      connections.add({ id: connectionId, deviceId }),
      () =>
        Effect.raceFirst(
          handler,
          auth.revoked(session).pipe(Effect.as(HttpServerResponse.empty())),
        ),
      (_, exit) =>
        Effect.gen(function* () {
          yield* connections.remove(connectionId);
          const reason = exit._tag === "Success" ? "closed" : "error";
          activity.connectionClosed(connectionId, Date.now(), reason);
          activity.record({ at: Date.now(), source: "gateway", level: "info", kind: "ws.closed", deviceId, connectionId, data: { reason } });
        }),
    );
  }).pipe(Effect.scoped),
);
