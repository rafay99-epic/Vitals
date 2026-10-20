import { PROTOCOL_VERSION, PairRequest } from "@vitals/contracts";
import * as Duration from "effect/Duration";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as HttpRouter from "effect/http/HttpRouter";
import * as HttpServerRequest from "effect/http/HttpServerRequest";
import * as HttpServerResponse from "effect/http/HttpServerResponse";
import * as HttpStaticServer from "effect/http/HttpStaticServer";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Auth } from "../auth/Auth.ts";
import { type Channel, GatewayConfig } from "../config.ts";
import { EventLog } from "../events/EventLog.ts";
import { loginHeader } from "../ws/route.ts";

const json = (body: unknown, status = 200) =>
  HttpServerResponse.jsonUnsafe(body, { status, headers: { "cache-control": "no-store" } });

const failure = (status: number, code: string, message: string) => json({ code, message }, status);

const sessionCookie = (channel: Channel) => `vitals_session_${channel}`;

const cookieOptions = { httpOnly: true, secure: true, sameSite: "strict", path: "/api" } as const;

const withSessionCookie = (response: HttpServerResponse.HttpServerResponse, channel: Channel, token: string, expiresAt: number) =>
  HttpServerResponse.setCookieUnsafe(response, sessionCookie(channel), token, {
    ...cookieOptions,
    maxAge: Duration.millis(Math.max(0, expiresAt - Date.now())),
  });

type Credential = { readonly token: string; readonly via: "bearer" | "cookie" };

const readCredential = (request: HttpServerRequest.HttpServerRequest, channel: Channel): Credential | null => {
  const bearer = request.headers["authorization"]?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (bearer !== undefined) return { token: bearer, via: "bearer" };
  const cookie = request.cookies[sessionCookie(channel)];
  return cookie === undefined || cookie === "" ? null : { token: cookie, via: "cookie" };
};

const crossSite = (request: HttpServerRequest.HttpServerRequest) => {
  const site = request.headers["sec-fetch-site"];
  return site !== undefined && site !== "same-origin" && site !== "none";
};

const authorized = <A, R>(handle: (credential: Credential, channel: Channel) => Effect.Effect<A, never, R>) =>
  Effect.gen(function* () {
    const request = yield* HttpServerRequest.HttpServerRequest;
    const auth = yield* Auth;
    const { channel } = yield* GatewayConfig;
    const identity = auth.checkIdentity(loginHeader(request));
    if (identity !== null) return failure(403, identity.reason, identity.message);
    const credential = readCredential(request, channel);
    if (credential === null) return failure(401, "credentials", "Not paired");
    if (credential.via === "cookie" && crossSite(request)) return failure(403, "origin", "Cross-site request refused");
    return yield* handle(credential, channel);
  });

const health = HttpRouter.add("GET", "/api/health", json({ ok: true, protocol: PROTOCOL_VERSION }));

const pair = HttpRouter.add(
  "POST",
  "/api/pair",
  Effect.gen(function* () {
    const request = yield* HttpServerRequest.HttpServerRequest;
    const auth = yield* Auth;
    const { channel } = yield* GatewayConfig;
    if (crossSite(request)) return failure(403, "origin", "Cross-site request refused");
    const body = yield* HttpServerRequest.schemaBodyJson(PairRequest).pipe(Effect.option);
    if (body._tag === "None") return failure(400, "invalid", "Invalid pairing request");
    const result = auth.pair(body.value, loginHeader(request));
    if ("reason" in result) return failure(result.reason === "identity" ? 403 : 401, result.reason, result.message);
    if (body.value.device.platform !== "web") return json(result);
    return withSessionCookie(json({ ...result, token: null }), channel, result.token, result.expiresAt);
  }),
);

const session = HttpRouter.add(
  "GET",
  "/api/session",
  Effect.gen(function* () {
    const request = yield* HttpServerRequest.HttpServerRequest;
    const auth = yield* Auth;
    const { channel } = yield* GatewayConfig;
    const identity = auth.checkIdentity(loginHeader(request));
    if (identity !== null) return failure(403, identity.reason, identity.message);
    const credential = readCredential(request, channel);
    const info = credential === null ? null : auth.session(credential.token);
    if (credential === null || info === null) {
      const empty = HttpServerResponse.empty({ status: 204, headers: { "cache-control": "no-store" } });
      return credential?.via === "cookie" ? HttpServerResponse.expireCookieUnsafe(empty, sessionCookie(channel), cookieOptions) : empty;
    }
    return credential.via === "cookie" ? withSessionCookie(json(info), channel, credential.token, info.expiresAt) : json(info);
  }),
);

const unpair = HttpRouter.add(
  "POST",
  "/api/unpair",
  authorized((credential, channel) =>
    Effect.gen(function* () {
      const auth = yield* Auth;
      const removed = yield* auth.unpair(credential.token);
      const response = removed ? json({ ok: true }) : failure(401, "credentials", "Session is not valid");
      return HttpServerResponse.expireCookieUnsafe(response, sessionCookie(channel), cookieOptions);
    }),
  ),
);

const alerts = HttpRouter.add(
  "GET",
  "/api/alerts",
  authorized((credential) =>
    Effect.gen(function* () {
      const auth = yield* Auth;
      const events = yield* EventLog;
      const info = auth.session(credential.token);
      if (info === null) return failure(401, "credentials", "Session is not valid");
      if (!info.scopes.includes("read")) return failure(403, "scope", "This device needs the read scope");
      const request = yield* HttpServerRequest.HttpServerRequest;
      const raw = Number(new URL(request.url, "http://gateway").searchParams.get("after") ?? "0");
      const after = Number.isSafeInteger(raw) && raw >= 0 ? raw : 0;
      const open = yield* events.openAlerts(after);
      const activity = yield* ActivityLog;
      activity.record({
        at: Date.now(),
        source: "gateway",
        level: "debug",
        kind: "alerts.polled",
        deviceId: info.deviceId,
        data: { after, lastSeq: open.lastSeq, alerts: open.alerts.length },
      });
      return json(open);
    }),
  ),
);

const ticket = HttpRouter.add(
  "POST",
  "/api/ws-ticket",
  authorized((credential) =>
    Effect.gen(function* () {
      const auth = yield* Auth;
      const result = auth.issueTicket(credential.token);
      if ("reason" in result) return failure(401, result.reason, result.message);
      return json(result);
    }),
  ),
);

export const apiRoutes = Layer.mergeAll(health, pair, session, unpair, alerts, ticket);

export const staticRoutes = (root: string | null) =>
  root === null ? Layer.empty : HttpStaticServer.layer({ root, spa: true, cacheControl: "public, max-age=300" });
