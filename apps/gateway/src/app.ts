import { mkdirSync } from "node:fs";
import { join } from "node:path";

import * as BunHttpServer from "@effect/platform-bun/BunHttpServer";
import * as Layer from "effect/Layer";
import * as HttpRouter from "effect/http/HttpRouter";

import * as ActivityLog from "./activity/ActivityLog.ts";
import * as Admin from "./admin/Admin.ts";
import * as Auth from "./auth/Auth.ts";
import * as Bridge from "./bridge/Bridge.ts";
import * as CommandService from "./commands/CommandService.ts";
import { GatewayConfig, type GatewayConfigShape } from "./config.ts";
import * as EventLog from "./events/EventLog.ts";
import * as AlertDispatcher from "./guard/AlertDispatcher.ts";
import { apiRoutes, staticRoutes } from "./http/routes.ts";
import * as Hubs from "./live/Hubs.ts";
import { ACTIVITY_MIGRATIONS, REMOTE_MIGRATIONS } from "./persistence/migrations.ts";
import { openDatabase } from "./persistence/sqlite.ts";
import * as Store from "./persistence/Store.ts";
import * as Serve from "./tailscale/Serve.ts";
import * as Connections from "./ws/Connections.ts";
import { wsRoute } from "./ws/route.ts";

export interface AppDependencies {
  readonly transport: Layer.Layer<Bridge.BridgeTransportService>;
  readonly push: AlertDispatcher.PushSender;
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
  const evented = EventLog.layer(activityDb).pipe(Layer.provideMerge(authed));
  const services = Layer.mergeAll(Hubs.layer, CommandService.layer, Serve.layer).pipe(Layer.provideMerge(evented));
  return Layer.mergeAll(Admin.layer, AlertDispatcher.layer(deps.push)).pipe(Layer.provideMerge(services));
};

const routes = (config: GatewayConfigShape) => Layer.mergeAll(apiRoutes, wsRoute, staticRoutes(config.webDir));

export const makeApp = (config: GatewayConfigShape, deps: AppDependencies) =>
  HttpRouter.serve(routes(config), { disableLogger: true, disableListenLog: true }).pipe(
    Layer.provide(
      BunHttpServer.layer({
        port: config.port,
        hostname: "127.0.0.1",
        gracefulShutdownTimeout: "2 seconds",
        websocket: { idleTimeout: 30, perMessageDeflate: false },
      }),
    ),
    Layer.provide(makeServices(config, deps)),
  );
