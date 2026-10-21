import type { GatewayStatus, TailscaleStep } from "@vitals/contracts";
import { bunRunner, consentUrl, findBinary, httpsUrl, isServing, serveOff, serveOn, status, type Runner, type TailscaleStatus } from "@vitals/tailscale";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Ref from "effect/Ref";
import * as Schedule from "effect/Schedule";
import * as Semaphore from "effect/Semaphore";
import * as Stream from "effect/Stream";
import { networkInterfaces } from "node:os";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Auth } from "../auth/Auth.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { GatewayConfig } from "../config.ts";
import { Lan } from "../lan/Lan.ts";
import { Connections } from "../ws/Connections.ts";

export class Serve extends Context.Service<Serve, { readonly status: Effect.Effect<GatewayStatus> }>()(
  "@vitals/gateway/Serve",
) {}

const POLL_SERVING = "5 minutes";
const POLL_DEGRADED = "30 seconds";
const ADDRESS_CHECK = "10 seconds";

const inTailnetRange = (address: string): boolean => {
  const [first, second] = address.split(".").map(Number);
  return first === 100 && second !== undefined && second >= 64 && second < 128;
};

const tailnetAddresses = (): string =>
  Object.values(networkInterfaces())
    .flatMap((entries) => entries ?? [])
    .filter((entry) => entry.family === "IPv4" && inTailnetRange(entry.address))
    .map((entry) => entry.address)
    .toSorted()
    .join(",");

const DETAIL: Record<TailscaleStep, string | null> = {
  install: "Tailscale CLI not found",
  start: "Tailscale is not running",
  signin: "Tailscale needs you to sign in",
  magicdns: "MagicDNS is off",
  https: "tailscale serve could not be configured",
  ready: null,
  external: "serve managed externally",
};

export const setupStep = (state: TailscaleStatus, mapped: boolean): TailscaleStep => {
  if (state.backendState === "NeedsLogin" || state.backendState === "NeedsMachineAuth") return "signin";
  if (!state.running) return "start";
  if (state.dnsName === null || !state.magicDns) return "magicdns";
  return mapped ? "ready" : "https";
};

export const layer = Layer.effect(
  Serve,
  Effect.gen(function* () {
    const config = yield* GatewayConfig;
    const auth = yield* Auth;
    const bridge = yield* Bridge;
    const activity = yield* ActivityLog;
    const connections = yield* Connections;
    const lan = yield* Lan;
    const current = yield* Ref.make<GatewayStatus>({
      serve: config.manageServe ? "starting" : "off",
      url: null,
      detail: null,
      ownerLogin: auth.ownerLogin(),
      clients: 0,
      lan: null,
      setup: { step: config.manageServe ? "start" : "external", url: null },
    });
    let consent: string | null = null;

    const log = (level: "info" | "warn" | "error", kind: string, data: Record<string, unknown>) =>
      activity.record({ at: Date.now(), source: "gateway", level, kind, data });

    const binary =
      config.tailscaleBin ??
      (yield* Effect.promise(() => findBinary(async (path) => Bun.file(path).exists())));
    const run: Runner | null = binary === null ? null : bunRunner(binary);

    const publish = (next: GatewayStatus) =>
      Effect.gen(function* () {
        const previous = yield* Ref.get(current);
        if (JSON.stringify(previous) === JSON.stringify(next)) return;
        yield* bridge.send({ t: "status", status: next });
        yield* Ref.set(current, next);
      });

    const ensureServe = (runner: Runner) =>
      Effect.gen(function* () {
        if (yield* Effect.promise(() => isServing(runner, config.servePort, config.port))) return true;
        const result = yield* Effect.promise(() => serveOn(runner, config.servePort, config.port));
        if (result.code !== 0) {
          consent = consentUrl(result.stderr) ?? consent;
          log("error", "tailscale.serve.error", { consent: consent !== null });
          return yield* Effect.fail(result.stderr);
        }
        consent = null;
        log("info", "tailscale.serve.up", { port: config.servePort });
        return true;
      }).pipe(
        Effect.retry({ schedule: Schedule.exponential("500 millis"), times: 4, while: () => consent === null }),
        Effect.orElseSucceed(() => false),
      );

    const lock = yield* Semaphore.make(1);

    const refresh = Effect.gen(function* () {
      const clients = yield* connections.count;
      const reachable = yield* lan.reachable;
      const base = { ownerLogin: auth.ownerLogin(), clients, lan: lan.info === null ? null : { ...lan.info, reachable } };
      if (!config.manageServe) {
        yield* publish({ ...base, serve: "off", url: null, detail: "serve managed externally", setup: { step: "external", url: null } });
        return;
      }
      if (run === null) {
        yield* publish({ ...base, serve: "degraded", url: null, detail: "Tailscale CLI not found", setup: { step: "install", url: null } });
        return;
      }
      const state = yield* Effect.promise(() => status(run));
      if (state.ownerLogin !== null && config.ownerLogin === null) yield* auth.setOwnerLogin(state.ownerLogin);
      const named = state.running && state.dnsName !== null && state.magicDns;
      const mapped = named ? yield* ensureServe(run) : false;
      const step = setupStep(state, mapped);
      yield* publish({
        ...base,
        ownerLogin: auth.ownerLogin(),
        serve: step === "ready" ? "serving" : "degraded",
        url: state.dnsName === null ? null : httpsUrl(state.dnsName, config.servePort),
        detail: DETAIL[step],
        setup: { step, url: step === "https" ? consent : null },
      });
    }).pipe(Semaphore.withPermit(lock));

    if (config.manageServe && run !== null) {
      yield* Effect.addFinalizer(() =>
        Effect.promise(() => serveOff(run, config.servePort)).pipe(
          Effect.tap(() => Effect.sync(() => log("info", "tailscale.serve.down", { port: config.servePort }))),
        ),
      );
    }

    const safeRefresh = refresh.pipe(
      Effect.catchCause((cause) => Effect.sync(() => log("error", "tailscale.refresh.failed", { cause: String(cause).slice(0, 400) }))),
    );
    yield* safeRefresh.pipe(
      Effect.andThen(Ref.get(current)),
      Effect.flatMap((state) => Effect.sleep(state.serve === "serving" ? POLL_SERVING : POLL_DEGRADED)),
      Effect.forever,
      Effect.forkScoped,
    );
    const addresses = yield* Ref.make(tailnetAddresses());
    yield* Effect.sync(tailnetAddresses).pipe(
      Effect.flatMap((next) => Ref.getAndSet(addresses, next).pipe(Effect.map((previous) => previous !== next))),
      Effect.flatMap((changed) => (changed ? safeRefresh : Effect.void)),
      Effect.repeat(Schedule.spaced(ADDRESS_CHECK)),
      Effect.forkScoped,
    );
    yield* connections.changes.pipe(Effect.andThen(safeRefresh), Effect.forever, Effect.forkScoped);
    yield* lan.reachableChanges.pipe(Stream.drop(1), Stream.runForEach(() => safeRefresh), Effect.forkScoped);

    return Serve.of({ status: Ref.get(current) });
  }),
);
