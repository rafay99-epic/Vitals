import { type Connection, Store } from "@vitals/client-runtime";
import { LAN_PORTS } from "@vitals/contracts";
import { forwardTo, loginTailnet, signOutTailnet, startTailnet, stopTailnet, tailnetNetworkChanged, tailnetState, tailnetSupported } from "@vitals/tailnet";
import * as Network from "expo-network";
import { AppState } from "react-native";

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

const NOT_SIGNED_IN = "Built-in Tailscale did not finish signing in";
const NEEDS_APPROVAL = "Approve this phone in the Tailscale admin console";
const SIGNED_OUT = new Set(["NeedsLogin", "NeedsMachineAuth", "Stopped"]);

let running: { readonly generation: number; readonly done: Promise<void> } | null = null;
// Bumped by stopTunnel so a start that is still signing in gives up instead of finishing.
let generation = 0;
// The last native stop, which a new start waits out so the stop can't land after it.
let stopping: Promise<void> = Promise.resolve();

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Polls the node until it runs, steering it there: asks for a sign-in URL when a saved login
 * went bad (tsnet only does that for a fresh node), and starts it again if a stop raced past.
 * A node waiting for admin approval keeps polling under its own message.
 */
const bringUp = async (target: string, mine: number): Promise<void> => {
  const current = () => mine === generation;
  await stopping;
  if (!current()) return;
  await startTailnet(nodeName());
  const deadline = Date.now() + GIVE_UP_MS;
  let askedLogin = false;
  while (current() && Date.now() < deadline) {
    const state = await tailnetState();
    if (!current()) return;
    switch (state.backend) {
      case "Running": {
        const port = await forwardTo(target);
        if (current()) tunnel.set({ _tag: "Ready", port });
        return;
      }
      case "NeedsLogin":
        if (state.loginUrl !== null) tunnel.set({ _tag: "NeedsLogin", url: state.loginUrl });
        else if (!askedLogin) {
          askedLogin = true;
          await loginTailnet();
        }
        break;
      case "NeedsMachineAuth":
        tunnel.set({ _tag: "Failed", reason: NEEDS_APPROVAL });
        break;
      case "Stopped":
      case "NoState":
        await startTailnet(nodeName());
        break;
      default:
        tunnel.set({ _tag: "Starting" });
    }
    await wait(POLL_MS);
  }
  if (!current()) return;
  const last = tunnel.get();
  tunnel.set(last._tag === "Failed" && last.reason === NEEDS_APPROVAL ? last : { _tag: "Failed", reason: NOT_SIGNED_IN });
};

export const startTunnel = (credentials: Credentials): Promise<void> => {
  const target = tunnelTarget(credentials);
  if (!tailnetSupported || target === null) {
    tunnel.set({ _tag: "Failed", reason: "Set up Tailscale on the Mac first" });
    return Promise.resolve();
  }
  if (tunnel.get()._tag === "Ready") return Promise.resolve();
  if (running?.generation === generation) return running.done;
  const mine = generation;
  tunnel.set({ _tag: "Starting" });
  const done = bringUp(target, mine)
    .catch((error: unknown) => {
      if (mine === generation) tunnel.set({ _tag: "Failed", reason: error instanceof Error ? error.message : "Built-in Tailscale failed" });
    })
    .finally(() => {
      if (running?.done === done) running = null;
    });
  running = { generation: mine, done };
  return done;
};

/**
 * Checks a running tunnel is still signed in and brings it back through sign-in if not (key
 * expired, node removed, approval revoked). Cheap: one local status read. runTunnelOnDemand
 * calls it on foreground and while the connection backs off over the tunnel.
 */
export const recheckTunnel = async (credentials: Credentials): Promise<void> => {
  if (tunnel.get()._tag !== "Ready") return;
  const state = await tailnetState();
  // Only states that need the bring-up loop: a slow status read (NoState) is not a lost login.
  if (!SIGNED_OUT.has(state.backend) || tunnel.get()._tag !== "Ready") return;
  tunnel.set({ _tag: "Starting" });
  await startTunnel(credentials);
};

/** Stops built-in Tailscale and its forward, cancelling a start that is still signing in. */
export const stopTunnel = async (): Promise<void> => {
  if (tunnel.get()._tag === "Off") return;
  generation += 1;
  tunnel.set({ _tag: "Off" });
  stopping = stopTailnet().catch(() => undefined);
  await stopping;
};

/**
 * Signs built-in Tailscale out and forgets its login, so the next pairing (maybe a Mac on
 * another tailnet) signs in fresh. Call when the phone forgets its Mac.
 */
export const signOutTunnel = async (): Promise<void> => {
  generation += 1;
  tunnel.set({ _tag: "Off" });
  stopping = signOutTailnet().catch(() => undefined);
  await stopping;
};

const STOP_AFTER_DIRECT_MS = 3 * 60_000;

/**
 * Runs built-in Tailscale only while it is needed. It starts when the Mac cannot be reached
 * directly (the connection is backing off, or the phone is off the local network) and stops
 * after three minutes of a direct Wi-Fi connection, or at once when the connection is parked
 * or refused, so it costs nothing at home or in the background. A failed start is retried on
 * the next network change, not on every heartbeat. While it runs, network switches are passed
 * to the node (Android tells it nothing on its own) and its sign-in is re-checked on
 * foreground and backoff.
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
    // Parked or refused: stop now. A timer would not fire, since Android pauses JS timers in the background.
    if (state._tag === "Suspended" || state._tag === "Revoked" || state._tag === "Incompatible") return void stopTunnel();
    if (state._tag !== "Ready" && state._tag !== "Connecting" && state._tag !== "Backoff") return;
    if (state._tag === "Backoff") void recheckTunnel(credentials());
    if (tunnel.get()._tag === "Failed" && !networkChanged) return;
    if (state._tag === "Backoff" || !localNetwork.get()) void startTunnel(credentials());
  };
  const networkMoved = () => {
    if (tunnel.get()._tag !== "Off") void tailnetNetworkChanged().catch(() => undefined);
  };
  const stopState = connection.state.subscribe(() => settle(false));
  const stopNetwork = localNetwork.subscribe(() => settle(true));
  const network = Network.addNetworkStateListener(networkMoved);
  const appState = AppState.addEventListener("change", (next) => {
    if (next !== "active" || credentials().builtInTailscale !== true) return;
    networkMoved();
    void recheckTunnel(credentials());
  });
  settle(false);
  return () => {
    stopState();
    stopNetwork();
    network.remove();
    appState.remove();
    cancelIdle();
    void stopTunnel();
  };
};
