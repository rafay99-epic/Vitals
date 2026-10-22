import {
  type Connection,
  type ConnectionOptions,
  type ConnectionState,
  createConnection,
  deviceKeyText,
  type Route,
  type RouteKind,
  Store,
} from "@vitals/client-runtime";
import { type ActivityLevel, type Command, type CommandReceipt, type LanEndpoint, type MacRoutes, CommandId, EventId } from "@vitals/contracts";
import type { KeyPair } from "@vitals/noise";
import { newId } from "@vitals/shared";
import { motion, type ToastTone } from "@vitals/ui";
import * as Schema from "effect/Schema";

import { localNetwork, nearby, nearbyEndpoints } from "../connection/nearby.ts";
import { tunnel } from "../connection/tunnel.ts";
import { openOutbox } from "../persistence/outbox";
import type { Credentials } from "../persistence/credentialsSchema.ts";
import { diagnostics, instrumentConnection } from "./diagnostics.ts";
import { MacEvents } from "./events.ts";
import { LiveData } from "./live.ts";

const makeCommandId = Schema.decodeUnknownSync(CommandId);
const makeEventId = Schema.decodeUnknownSync(EventId);
const FLUSH_MS = 10_000;

export const CLIENT_VERSION = "1.0.0";

export interface Toast {
  readonly message: string;
  readonly tone: ToastTone;
  readonly at: number;
}

const sameEndpoint = (left: LanEndpoint, right: LanEndpoint) => left.host === right.host && left.port === right.port;

const uniqueEndpoints = (endpoints: ReadonlyArray<LanEndpoint>): ReadonlyArray<LanEndpoint> =>
  endpoints.filter((endpoint, index) => endpoints.findIndex((other) => sameEndpoint(other, endpoint)) === index);

const lanEndpointsOf = (credentials: Credentials): ReadonlyArray<LanEndpoint> =>
  localNetwork.get() ? uniqueEndpoints([...nearbyEndpoints(credentials.macKey), ...(credentials.lan ?? [])]) : [];

const tunnelRoutes = (credentials: Credentials): ReadonlyArray<Route> => {
  const state = tunnel.get();
  return credentials.builtInTailscale === true && state._tag === "Ready" ? [{ _tag: "Lan", host: "127.0.0.1", port: state.port, tunnel: true }] : [];
};

export const routesOf = (credentials: Credentials): ReadonlyArray<Route> => [
  ...lanEndpointsOf(credentials).map((endpoint): Route => ({ _tag: "Lan", host: endpoint.host, port: endpoint.port })),
  ...tunnelRoutes(credentials),
  ...(credentials.baseUrl === null ? [] : [{ _tag: "Tailnet", baseUrl: credentials.baseUrl } satisfies Route]),
];

const learnRoutes = (credentials: Credentials, routes: MacRoutes, via: RouteKind): Credentials => {
  const pinned = credentials.macKey ?? null;
  const rekeyed = pinned !== null && pinned !== routes.key;
  if (rekeyed && via !== "tailnet") return credentials;
  return {
    ...credentials,
    ...(rekeyed ? { lanBound: false } : {}),
    macKey: routes.key,
    lan: routes.lan,
    baseUrl: routes.tailnet ?? credentials.baseUrl,
    owner: routes.owner ?? credentials.owner ?? null,
  };
};

export class Remote {
  readonly connection: Connection;
  readonly live: LiveData;
  readonly events: MacEvents;
  readonly toast = new Store<Toast | null>(null);
  readonly link: Store<Credentials>;
  private disposed = false;
  private readonly outbox = openOutbox();
  private readonly flushTimer: ReturnType<typeof setInterval>;
  private flushing = false;
  private readonly stopSampleClock: (() => void) | null;

  private readonly stopNearbyWatch: () => void;
  private readonly stopTunnelWatch: () => void;
  private readonly relink: (next: Credentials) => void;
  private readonly stopBind: () => void;

  constructor(
    credentials: Credentials,
    deviceKey: KeyPair | null,
    webSocket: ConnectionOptions["webSocket"],
    onLink: (credentials: Credentials) => void,
  ) {
    this.link = new Store(credentials);
    const relink = (next: Credentials) => {
      if (JSON.stringify(next) === JSON.stringify(this.link.get())) return;
      this.link.set(next);
      onLink(next);
    };
    this.relink = relink;
    this.connection = instrumentConnection(
      createConnection({
        routes: () => routesOf(this.link.get()),
        token: credentials.token,
        macKey: () => this.link.get().macKey ?? null,
        deviceKey,
        onRoutes: (routes, via) => relink(learnRoutes(this.link.get(), routes, via)),
        lanEnrolled: () => this.link.get().lanBound === true,
        onLanUnknown: () => relink({ ...this.link.get(), lanBound: false }),
        clientVersion: CLIENT_VERSION,
        webSocket,
        onTransition: (from, to) => {
          if (sameShape(from, to)) return;
          diagnostics.transition(from, to);
          this.record(to._tag === "Backoff" ? "warn" : "info", "client.conn.state", transitionData(from, to));
        },
      }),
    );
    this.live = new LiveData(this.connection);
    this.stopSampleClock = diagnostics.enabled ? this.live.latest.subscribe(() => diagnostics.sample(Date.now())) : null;
    this.events = new MacEvents(this.connection);
    this.flushTimer = setInterval(() => void this.flush(), FLUSH_MS);
    this.stopTunnelWatch = tunnel.subscribe(() => {
      if (tunnel.get()._tag === "Ready") this.connection.wake("network");
    });
    this.stopNearbyWatch = nearby.subscribe(() => {
      const state = this.connection.state.get();
      if (state._tag === "Ready" && state.route === "lan") return;
      if (nearbyEndpoints(this.link.get().macKey).length > 0) this.connection.wake("network");
    });
    let binding = false;
    this.stopBind = this.connection.state.subscribe(() => {
      const state = this.connection.state.get();
      if (binding || deviceKey === null || this.link.get().lanBound === true) return;
      if (state._tag !== "Ready" || state.route !== "tailnet" || state.hello.routes === undefined) return;
      binding = true;
      void this.connection.call((client) => client["device.lanKey"]({ key: deviceKeyText(deviceKey) })).then((result) => {
        binding = false;
        if (!result.ok) return;
        relink({ ...this.link.get(), lanBound: true });
        this.connection.wake("network");
      });
    });
  }

  setBuiltInTailscale(enabled: boolean): void {
    this.relink({ ...this.link.get(), builtInTailscale: enabled });
  }

  get credentials(): Credentials {
    return this.link.get();
  }

  record(level: ActivityLevel, kind: string, data: Record<string, unknown> = {}): void {
    if (this.disposed) return;
    this.outbox.push({ eventId: makeEventId(newId()), at: Date.now(), level, kind, data });
  }

  async run(command: Command): Promise<CommandReceipt | null> {
    this.record("info", "client.ui.command", { kind: command._tag });
    const result = await this.connection.call((client) => client["command.run"]({ commandId: makeCommandId(newId()), command }));
    if (result.ok) {
      this.events.receipt(result.value);
      if (result.value.status === "failed") this.show(result.value.error ?? `${command._tag} failed`, "bad");
      return result.value;
    }
    this.show(result.error.message, "bad");
    this.record("warn", "client.rpc.error", { method: "command.run", tag: result.error._tag });
    return null;
  }

  /** Cancels a pending order. Resolves true once the Mac confirms; a failure is shown and resolves false. */
  async cancel(receipt: CommandReceipt): Promise<boolean> {
    const result = await this.connection.call((client) => client["command.cancel"]({ commandId: receipt.id }));
    if (result.ok) this.events.receipt(result.value);
    else this.show(result.error.message, "bad");
    return result.ok;
  }

  private toastTimer: ReturnType<typeof setTimeout> | null = null;

  show(message: string, tone: Toast["tone"] = "ok"): void {
    const toast = { message, tone, at: Date.now() };
    this.toast.set(toast);
    if (this.toastTimer !== null) clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => {
      if (this.toast.get() === toast) this.toast.set(null);
    }, motion.toastHold);
  }

  async flush(): Promise<void> {
    if (this.flushing || this.connection.state.get()._tag !== "Ready") return;
    const batch = this.outbox.take(200);
    if (batch.length === 0) return;
    this.flushing = true;
    const result = await this.connection.call((client) => client["activity.ingest"]({ events: batch }));
    if (result.ok) this.outbox.remove(batch.map((event) => event.eventId));
    this.flushing = false;
  }

  discardQueued(): void {
    this.outbox.clear();
  }

  dispose(): void {
    this.disposed = true;
    this.stopNearbyWatch();
    this.stopTunnelWatch();
    this.stopBind();
    this.stopSampleClock?.();
    clearInterval(this.flushTimer);
    if (this.toastTimer !== null) clearTimeout(this.toastTimer);
    this.live.dispose();
    this.events.dispose();
    this.connection.dispose();
  }
}

const sameShape = (from: ConnectionState, to: ConnectionState): boolean =>
  from._tag === "Ready" && to._tag === "Ready" && from.route === to.route;

const transitionData = (from: ConnectionState, to: ConnectionState): Record<string, unknown> => ({
  from: from._tag,
  to: to._tag,
  ...(to._tag === "Backoff" ? { attempt: to.attempt, delayMs: to.retryAt - Date.now(), reason: to.reason, failures: to.failures } : {}),
  ...(to._tag === "Ready" ? { route: to.route } : {}),
});
