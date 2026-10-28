import { Store } from "@vitals/client-runtime";
import type { LanEndpoint } from "@vitals/contracts";
import { browse, type FoundMac } from "@vitals/discovery";

import { note } from "../state/journal.ts";

export const nearby = new Store<ReadonlyArray<FoundMac>>([]);

export const localNetwork = new Store<boolean>(true);

let stop: (() => void) | null = null;

export const startNearby = (): void => {
  if (stop !== null) return;
  stop = browse((event) => {
    switch (event._tag) {
      case "Found":
        note("nearby", `found ${event.mac.txt["n"] ?? event.mac.name} at ${event.mac.host}:${String(event.mac.port)}, ${event.mac.txt["c"] ?? "stable"} build, key ${(macKeyOf(event.mac) ?? "none").slice(0, 8)}`);
        nearby.set([...nearby.get().filter((mac) => mac.name !== event.mac.name), event.mac]);
        return;
      case "Lost":
        note("nearby", `lost ${event.name}`);
        nearby.set(nearby.get().filter((mac) => mac.name !== event.name));
        return;
      case "Failed":
        note("nearby", `looking failed: ${event.reason}`);
        return;
    }
  });
};

export const stopNearby = (): void => {
  stop?.();
  stop = null;
  // Browsing again starts from nothing; a Mac seen on the last Wi-Fi must not linger.
  nearby.set([]);
};

export const macKeyOf = (mac: FoundMac): string | null => mac.txt["k"] ?? null;

export const nearbyEndpoints = (macKey: string | null | undefined): ReadonlyArray<LanEndpoint> =>
  macKey === null || macKey === undefined
    ? []
    : nearby
        .get()
        .filter((mac) => macKeyOf(mac) === macKey)
        .map((mac) => ({ host: mac.host, port: mac.port }));
