import { toBunServerRequest } from "@effect/platform-bun/BunHttpServerRequest";
import * as Effect from "effect/Effect";
import * as HttpRouter from "effect/http/HttpRouter";
import * as HttpServerRequest from "effect/http/HttpServerRequest";
import * as HttpServerResponse from "effect/http/HttpServerResponse";

import { DropStore } from "./DropStore.ts";

export const dropRoutes = HttpRouter.add(
  "*",
  "/api/drop/:dropId/:fileId",
  Effect.gen(function* () {
    const request = yield* HttpServerRequest.HttpServerRequest;
    const drops = yield* DropStore;
    const response = yield* Effect.promise(() => drops.handle(toBunServerRequest(request), "tailnet"));
    return HttpServerResponse.raw(response);
  }),
);
