import { NativeModule, requireOptionalNativeModule } from "expo";

import type { DiscoveryEvent, FoundMac, LocalNetworkPermission } from "./types.ts";

export type { DiscoveryEvent, FoundMac, LocalNetworkPermission } from "./types.ts";

declare class VitalsDiscovery extends NativeModule<{
  found: (mac: FoundMac) => void;
  lost: (event: { name: string }) => void;
  failed: (event: { reason: string }) => void;
}> {
  start(): void;
  stop(): void;
  requestLocalNetwork(): Promise<LocalNetworkPermission>;
}

const native = requireOptionalNativeModule<VitalsDiscovery>("VitalsDiscovery");

const listeners = new Set<(event: DiscoveryEvent) => void>();
const found = new Map<string, FoundMac>();

const emit = (event: DiscoveryEvent) => listeners.forEach((listener) => listener(event));

native?.addListener("found", (mac) => {
  found.set(mac.name, mac);
  emit({ _tag: "Found", mac });
});
native?.addListener("lost", ({ name }) => {
  found.delete(name);
  emit({ _tag: "Lost", name });
});
native?.addListener("failed", ({ reason }) => emit({ _tag: "Failed", reason }));

export const discoverySupported = native !== null;

export const requestLocalNetwork = async (): Promise<LocalNetworkPermission> =>
  native?.requestLocalNetwork() ?? "unsupported";

export const browse = (onEvent: (event: DiscoveryEvent) => void): (() => void) => {
  if (native === null) return () => {};
  const listener = (event: DiscoveryEvent) => onEvent(event);
  listeners.add(listener);
  found.forEach((mac) => listener({ _tag: "Found", mac }));
  if (listeners.size === 1) native.start();
  return () => {
    if (!listeners.delete(listener) || listeners.size > 0) return;
    found.clear();
    native.stop();
  };
};
