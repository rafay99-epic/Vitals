import { Store } from "@vitals/client-runtime";
import { LAN_PORTS } from "@vitals/contracts";
import { forwardTo, startTailnet, tailnetState, tailnetSupported } from "@vitals/tailnet";

import { deviceInfo } from "../lib/device.ts";
import { isDevBuild } from "../lib/variant";
import type { Credentials } from "../persistence/credentialsSchema.ts";

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
  const port = credentials.lan?.[0]?.port ?? (isDevBuild ? LAN_PORTS.dev : LAN_PORTS.stable);
  return `${host}:${String(port)}`;
};

let running: Promise<void> | null = null;

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const bringUp = async (target: string): Promise<void> => {
  tunnel.set({ _tag: "Starting" });
  await startTailnet(nodeName());
  const deadline = Date.now() + GIVE_UP_MS;
  while (Date.now() < deadline) {
    const state = await tailnetState();
    if (state.backend === "Running") {
      tunnel.set({ _tag: "Ready", port: await forwardTo(target) });
      return;
    }
    tunnel.set(state.loginUrl === null ? { _tag: "Starting" } : { _tag: "NeedsLogin", url: state.loginUrl });
    await wait(POLL_MS);
  }
  tunnel.set({ _tag: "Failed", reason: "Built-in Tailscale did not finish signing in" });
};

export const startTunnel = (credentials: Credentials): Promise<void> => {
  const target = tunnelTarget(credentials);
  if (!tailnetSupported || target === null) {
    tunnel.set({ _tag: "Failed", reason: "Set up Tailscale on the Mac first" });
    return Promise.resolve();
  }
  if (tunnel.get()._tag === "Ready") return Promise.resolve();
  running ??= bringUp(target)
    .catch((error: unknown) => tunnel.set({ _tag: "Failed", reason: error instanceof Error ? error.message : "Built-in Tailscale failed" }))
    .finally(() => {
      running = null;
    });
  return running;
};
