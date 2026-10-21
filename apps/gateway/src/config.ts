import { LAN_PORTS } from "@vitals/contracts";
import * as Context from "effect/Context";

export type Channel = "stable" | "nightly" | "dev";

export const MAX_FRAME_BYTES = 1024 * 1024;

export interface GatewayConfigShape {
  readonly channel: Channel;
  readonly port: number;
  readonly servePort: number;
  readonly dataDir: string;
  readonly webDir: string | null;
  readonly tailscaleBin: string | null;
  readonly manageServe: boolean;
  readonly ownerLogin: string | null;
  readonly lanPort: number | null;
}

export class GatewayConfig extends Context.Service<GatewayConfig, GatewayConfigShape>()("@vitals/gateway/GatewayConfig") {}

const SERVE_PORTS: Record<Channel, number> = { stable: 7443, nightly: 7444, dev: 7445 };
const LOCAL_PORTS: Record<Channel, number> = { stable: 47800, nightly: 47801, dev: 47802 };

const parseChannel = (value: string | undefined): Channel =>
  value === "stable" || value === "nightly" || value === "dev" ? value : "dev";

const parsePort = (value: string | undefined, fallback: number): number => {
  const port = Number(value);
  return Number.isInteger(port) && port > 0 && port < 65536 ? port : fallback;
};

export const configFromEnv = (env: Record<string, string | undefined>): GatewayConfigShape => {
  const channel = parseChannel(env["VITALS_CHANNEL"]);
  const dataDir = env["VITALS_REMOTE_DATA_DIR"];
  if (dataDir === undefined || dataDir.length === 0) {
    throw new Error("VITALS_REMOTE_DATA_DIR is required");
  }
  return {
    channel,
    port: parsePort(env["VITALS_REMOTE_PORT"], LOCAL_PORTS[channel]),
    servePort: parsePort(env["VITALS_REMOTE_SERVE_PORT"], SERVE_PORTS[channel]),
    dataDir,
    webDir: env["VITALS_REMOTE_WEB_DIR"] ?? null,
    tailscaleBin: env["VITALS_TAILSCALE_BIN"] ?? null,
    manageServe: env["VITALS_REMOTE_MANAGE_SERVE"] !== "0",
    ownerLogin: env["VITALS_REMOTE_OWNER"] ?? null,
    lanPort: env["VITALS_REMOTE_LAN"] === "0" ? null : parsePort(env["VITALS_REMOTE_LAN_PORT"], LAN_PORTS[channel]),
  };
};
