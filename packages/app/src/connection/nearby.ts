import { Store } from "@vitals/client-runtime";
import type { LanEndpoint } from "@vitals/contracts";
import { browse, type FoundMac } from "@vitals/discovery";

export const nearby = new Store<ReadonlyArray<FoundMac>>([]);

export const localNetwork = new Store<boolean>(true);

let stop: (() => void) | null = null;

export const startNearby = (): void => {
  if (stop !== null) return;
  stop = browse((event) => {
    switch (event._tag) {
      case "Found":
        nearby.set([...nearby.get().filter((mac) => mac.name !== event.mac.name), event.mac]);
        return;
      case "Lost":
        nearby.set(nearby.get().filter((mac) => mac.name !== event.name));
        return;
      case "Failed":
        return;
    }
  });
};

export const stopNearby = (): void => {
  stop?.();
  stop = null;
};

export const macKeyOf = (mac: FoundMac): string | null => mac.txt["k"] ?? null;

export const nearbyEndpoints = (macKey: string | null | undefined): ReadonlyArray<LanEndpoint> =>
  macKey === null || macKey === undefined
    ? []
    : nearby
        .get()
        .filter((mac) => macKeyOf(mac) === macKey)
        .map((mac) => ({ host: mac.host, port: mac.port }));
