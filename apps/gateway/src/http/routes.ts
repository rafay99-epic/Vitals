import { PROTOCOL_VERSION, PairRequest } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as HttpRouter from "effect/http/HttpRouter";
import * as HttpServerRequest from "effect/http/HttpServerRequest";
import * as HttpServerResponse from "effect/http/HttpServerResponse";
import * as HttpStaticServer from "effect/http/HttpStaticServer";

import { Auth } from "../auth/Auth.ts";
import { loginHeader } from "../ws/route.ts";

const json = (body: unknown, status = 200) =>
  HttpServerResponse.jsonUnsafe(body, { status, headers: { "cache-control": "no-store" } });

const health = HttpRouter.add("GET", "/api/health", json({ ok: true, protocol: PROTOCOL_VERSION }));

const pair = HttpRouter.add(
  "POST",
  "/api/pair",
  Effect.gen(function* () {
    const request = yield* HttpServerRequest.HttpServerRequest;
    const auth = yield* Auth;
    const body = yield* HttpServerRequest.schemaBodyJson(PairRequest).pipe(Effect.option);
    if (body._tag === "None") return json({ code: "invalid", message: "Invalid pairing request" }, 400);
    const result = auth.pair(body.value, loginHeader(request));
    if ("reason" in result) return json({ code: result.reason, message: result.message }, result.reason === "identity" ? 403 : 401);
    return json(result);
  }),
);

const ticket = HttpRouter.add(
  "POST",
  "/api/ws-ticket",
  Effect.gen(function* () {
    const request = yield* HttpServerRequest.HttpServerRequest;
    const auth = yield* Auth;
    const identity = auth.checkIdentity(loginHeader(request));
    if (identity !== null) return json({ code: identity.reason, message: identity.message }, 403);
    const bearer = request.headers["authorization"]?.replace(/^Bearer\s+/i, "") ?? "";
    const result = auth.issueTicket(bearer);
    if ("reason" in result) return json({ code: result.reason, message: result.message }, 401);
    return json(result);
  }),
);

export const apiRoutes = Layer.mergeAll(health, pair, ticket);

export const staticRoutes = (root: string | null) =>
  root === null ? Layer.empty : HttpStaticServer.layer({ root, spa: true, cacheControl: "public, max-age=300" });
