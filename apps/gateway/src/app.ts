import { mkdirSync } from "node:fs";
import { join } from "node:path";

import * as BunHttpServer from "@effect/platform-bun/BunHttpServer";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as HttpRouter from "effect/http/HttpRouter";

import * as ActivityLog from "./activity/ActivityLog.ts";
import * as Admin from "./admin/Admin.ts";
import * as Auth from "./auth/Auth.ts";
import * as Bridge from "./bridge/Bridge.ts";
import * as ClipStore from "./clips/ClipStore.ts";
import * as CommandService from "./commands/CommandService.ts";
import { GatewayConfig, type GatewayConfigShape, MAX_FRAME_BYTES } from "./config.ts";
import * as EventLog from "./events/EventLog.ts";
import { apiRoutes, staticRoutes } from "./http/routes.ts";
import * as Lan from "./lan/Lan.ts";
import * as Hubs from "./live/Hubs.ts";
import { ACTIVITY_MIGRATIONS, REMOTE_MIGRATIONS } from "./persistence/migrations.ts";
import { openDatabase } from "./persistence/sqlite.ts";
import * as Store from "./persistence/Store.ts";
import * as Serve from "./tailscale/Serve.ts";
import * as Connections from "./ws/Connections.ts";
import { wsRoute } from "./ws/route.ts";

export interface AppDependencies {
  readonly transport: Layer.Layer<Bridge.BridgeTransportService>;
}

const makeServices = (config: GatewayConfigShape, deps: AppDependencies) => {
  mkdirSync(config.dataDir, { recursive: true, mode: 0o700 });
  const remoteDb = openDatabase(join(config.dataDir, "remote.db"), REMOTE_MIGRATIONS);
  const activityDb = openDatabase(join(config.dataDir, "activity.db"), ACTIVITY_MIGRATIONS);

  const core = Layer.mergeAll(
    Layer.succeed(GatewayConfig, config),
    ActivityLog.layer(activityDb),
    Store.layer(remoteDb),
    Connections.layer,
    deps.transport,
  );
  const bridged = Bridge.layer.pipe(Layer.provideMerge(core));
  const authed = Auth.layer(config.ownerLogin).pipe(Layer.provideMerge(bridged));
  const lanned = Lan.layer.pipe(Layer.provideMerge(authed));
  const evented = EventLog.layer(activityDb).pipe(Layer.provideMerge(lanned));
  const services = Layer.mergeAll(
    Hubs.layer,
    CommandService.layer,
    Serve.layer,
    ClipStore.layer(remoteDb),
  ).pipe(Layer.provideMerge(evented));
  const ready = Layer.effectDiscard(
    Effect.gen(function* () {
      const bridge = yield* Bridge.Bridge;
      yield* bridge.send({ t: "hello", v: 1 });
    }),
  );
  return Layer.mergeAll(Admin.layer, ready).pipe(Layer.provideMerge(services));
};

const routes = (config: GatewayConfigShape) => Layer.mergeAll(apiRoutes, wsRoute, staticRoutes(config.webDir));

export const makeApp = (config: GatewayConfigShape, deps: AppDependencies) =>
  HttpRouter.serve(routes(config), { disableLogger: true, disableListenLog: true }).pipe(
    Layer.provide(
      BunHttpServer.layer({
        port: config.port,
        hostname: "127.0.0.1",
        gracefulShutdownTimeout: "2 seconds",
        websocket: { idleTimeout: 30, perMessageDeflate: false, maxPayloadLength: MAX_FRAME_BYTES },
      }),
    ),
    Layer.provide(makeServices(config, deps)),
  );
