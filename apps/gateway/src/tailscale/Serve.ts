import type { GatewayStatus } from "@vitals/contracts";
import { bunRunner, findBinary, httpsUrl, isServing, serveOff, serveOn, status, type Runner } from "@vitals/tailscale";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Ref from "effect/Ref";
import * as Schedule from "effect/Schedule";
import * as Semaphore from "effect/Semaphore";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Auth } from "../auth/Auth.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { GatewayConfig } from "../config.ts";
import { Connections } from "../ws/Connections.ts";

export class Serve extends Context.Service<Serve, { readonly status: Effect.Effect<GatewayStatus> }>()(
  "@vitals/gateway/Serve",
) {}

const POLL = "30 seconds";

export const layer = Layer.effect(
  Serve,
  Effect.gen(function* () {
    const config = yield* GatewayConfig;
    const auth = yield* Auth;
    const bridge = yield* Bridge;
    const activity = yield* ActivityLog;
    const connections = yield* Connections;
    const current = yield* Ref.make<GatewayStatus>({
      serve: config.manageServe ? "starting" : "off",
      url: null,
      detail: null,
      ownerLogin: auth.ownerLogin(),
      clients: 0,
    });

    const log = (level: "info" | "warn" | "error", kind: string, data: Record<string, unknown>) =>
      activity.record({ at: Date.now(), source: "gateway", level, kind, data });

    const binary =
      config.tailscaleBin ??
      (yield* Effect.promise(() => findBinary(async (path) => Bun.file(path).exists())));
    const run: Runner | null = binary === null ? null : bunRunner(binary);

    const publish = (next: GatewayStatus) =>
      Effect.gen(function* () {
        const previous = yield* Ref.getAndSet(current, next);
        if (JSON.stringify(previous) !== JSON.stringify(next)) yield* bridge.send({ t: "status", status: next });
      });

    const ensureServe = (runner: Runner) =>
      Effect.gen(function* () {
        if (yield* Effect.promise(() => isServing(runner, config.servePort, config.port))) return true;
        const result = yield* Effect.promise(() => serveOn(runner, config.servePort, config.port));
        if (result.code !== 0) {
          log("error", "tailscale.serve.error", { stderr: result.stderr.slice(0, 400) });
          return yield* Effect.fail(result.stderr);
        }
        log("info", "tailscale.serve.up", { port: config.servePort });
        return true;
      }).pipe(
        Effect.retry({ schedule: Schedule.exponential("500 millis"), times: 4 }),
        Effect.orElseSucceed(() => false),
      );

    const lock = yield* Semaphore.make(1);

    const refresh = Effect.gen(function* () {
      const clients = yield* connections.count;
      if (!config.manageServe) {
        yield* publish({ serve: "off", url: null, detail: "serve managed externally", ownerLogin: auth.ownerLogin(), clients });
        return;
      }
      if (run === null) {
        yield* publish({ serve: "degraded", url: null, detail: "Tailscale CLI not found", ownerLogin: null, clients });
        return;
      }
      const state = yield* Effect.promise(() => status(run));
      if (state.ownerLogin !== null && config.ownerLogin === null) auth.setOwnerLogin(state.ownerLogin);
      const mapped = state.running ? yield* ensureServe(run) : false;
      const ok = state.running && state.dnsName !== null && state.magicDns && mapped;
      const detail = !state.running
        ? "Tailscale is not running"
        : !state.magicDns
          ? "MagicDNS is off"
          : !mapped
            ? "tailscale serve could not be configured"
            : null;
      yield* publish({
        serve: ok ? "serving" : "degraded",
        url: state.dnsName === null ? null : httpsUrl(state.dnsName, config.servePort),
        detail,
        ownerLogin: auth.ownerLogin(),
        clients,
      });
    }).pipe(Semaphore.withPermit(lock));

    if (config.manageServe && run !== null) {
      yield* Effect.addFinalizer(() =>
        Effect.promise(() => serveOff(run, config.servePort)).pipe(
          Effect.tap(() => Effect.sync(() => log("info", "tailscale.serve.down", { port: config.servePort }))),
        ),
      );
    }

    yield* refresh.pipe(Effect.repeat(Schedule.spaced(POLL)), Effect.forkScoped);
    yield* connections.changes.pipe(Effect.andThen(refresh), Effect.forever, Effect.forkScoped);

    return Serve.of({ status: Ref.get(current) });
  }),
);
