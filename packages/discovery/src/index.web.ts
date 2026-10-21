import type { DiscoveryEvent, LocalNetworkPermission } from "./types.ts";

export type { DiscoveryEvent, FoundMac, LocalNetworkPermission } from "./types.ts";

export const discoverySupported = false;

export const requestLocalNetwork = async (): Promise<LocalNetworkPermission> => "unsupported";

export const browse = (_onEvent: (event: DiscoveryEvent) => void): (() => void) => () => {};
