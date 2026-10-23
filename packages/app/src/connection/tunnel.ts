import { type Connection, Store } from "@vitals/client-runtime";
import { LAN_PORTS } from "@vitals/contracts";
import { forwardTo, startTailnet, stopTailnet, tailnetState, tailnetSupported } from "@vitals/tailnet";

import { deviceInfo } from "../lib/device.ts";
import { channel } from "../lib/variant";
import type { Credentials } from "../persistence/credentialsSchema.ts";
import { localNetwork } from "./nearby.ts";

export type Tunnel =
  | { readonly _tag: "Off" }
  | { readonly _tag: "Starting" }
  | { readonly _tag: "NeedsLogin"; readonly url: string }
  | { readonly _tag: "Ready"; readonly port: number }
  | { readonly _tag: "Failed"; readonly reason: string };

export const tunnel = new Store<Tunnel>({ _tag: "Off" });

export { tailnetSupported };

const POLL_MS = 2_000;
const GIVE_UP_MS = 10 * 60_000;

const nodeName = (): string =>
  `vitals-${deviceInfo()
    .name.toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 40)}`;

const tunnelTarget = (credentials: Credentials): string | null => {
  if (credentials.baseUrl === null) return null;
  const host = new URL(credentials.baseUrl).hostname;
  const port = credentials.lan?.[0]?.port ?? LAN_PORTS[channel];
  return `${host}:${String(port)}`;
};

let running: Promise<void> | null = null;
// Bumped by stopTunnel so a start that is still signing in gives up instead of finishing.
let generation = 0;

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const bringUp = async (target: string, mine: number): Promise<void> => {
  const current = () => mine === generation;
  tunnel.set({ _tag: "Starting" });
  await startTailnet(nodeName());
  const deadline = Date.now() + GIVE_UP_MS;
  while (current() && Date.now() < deadline) {
    const state = await tailnetState();
    if (!current()) return;
    if (state.backend === "Running") {
      const port = await forwardTo(target);
      if (current()) tunnel.set({ _tag: "Ready", port });
      return;
    }
    tunnel.set(state.loginUrl === null ? { _tag: "Starting" } : { _tag: "NeedsLogin", url: state.loginUrl });
    await wait(POLL_MS);
  }
  if (current()) tunnel.set({ _tag: "Failed", reason: "Built-in Tailscale did not finish signing in" });
};

export const startTunnel = (credentials: Credentials): Promise<void> => {
  const target = tunnelTarget(credentials);
  if (!tailnetSupported || target === null) {
    tunnel.set({ _tag: "Failed", reason: "Set up Tailscale on the Mac first" });
    return Promise.resolve();
  }
  if (tunnel.get()._tag === "Ready") return Promise.resolve();
  const mine = generation;
  running ??= bringUp(target, mine)
    .catch((error: unknown) => {
      if (mine === generation) tunnel.set({ _tag: "Failed", reason: error instanceof Error ? error.message : "Built-in Tailscale failed" });
    })
    .finally(() => {
      running = null;
    });
  return running;
};

/** Stops built-in Tailscale and its forward, cancelling a start that is still signing in. */
export const stopTunnel = async (): Promise<void> => {
  if (tunnel.get()._tag === "Off") return;
  generation += 1;
  tunnel.set({ _tag: "Off" });
  await stopTailnet().catch(() => undefined);
};

const STOP_AFTER_DIRECT_MS = 3 * 60_000;

/**
 * Runs built-in Tailscale only while it is needed. It starts when the Mac cannot be reached
 * directly (the connection is backing off, or the phone is off the local network) and stops
 * after three minutes of a direct Wi-Fi connection, so it costs nothing at home. A failed
 * start is retried on the next network change, not on every heartbeat.
 */
export const runTunnelOnDemand = (connection: Connection, credentials: () => Credentials): (() => void) => {
  let idle: ReturnType<typeof setTimeout> | null = null;
  const cancelIdle = () => {
    if (idle !== null) clearTimeout(idle);
    idle = null;
  };
  const settle = (networkChanged: boolean) => {
    if (credentials().builtInTailscale !== true) return;
    const state = connection.state.get();
    if (state._tag === "Ready" && state.route === "lan") {
      if (tunnel.get()._tag === "Off") return;
      idle ??= setTimeout(() => {
        idle = null;
        void stopTunnel();
      }, STOP_AFTER_DIRECT_MS);
      return;
    }
    cancelIdle();
    if (state._tag !== "Ready" && state._tag !== "Connecting" && state._tag !== "Backoff") return;
    if (tunnel.get()._tag === "Failed" && !networkChanged) return;
    if (state._tag === "Backoff" || !localNetwork.get()) void startTunnel(credentials());
  };
  const stopState = connection.state.subscribe(() => settle(false));
  const stopNetwork = localNetwork.subscribe(() => settle(true));
  settle(false);
  return () => {
    stopState();
    stopNetwork();
    cancelIdle();
    void stopTunnel();
  };
};
