import { fetchSession, unpair } from "@vitals/client-runtime";

import type { Credentials } from "./credentialsSchema.ts";

const RETRY_MS = [1_000, 2_000, 5_000, 10_000, 30_000] as const;

const origin = (): string => globalThis.location.origin;

export const loadCredentials = async (): Promise<Credentials | null> => {
  for (const delay of [0, ...RETRY_MS]) {
    await new Promise((resolve) => setTimeout(resolve, delay));
    const lookup = await fetchSession(origin(), null);
    if (lookup._tag === "Unpaired") return null;
    if (lookup._tag === "Paired") {
      const { deviceId, scopes, pairedAt } = lookup.session;
      return { baseUrl: origin(), token: null, deviceId, scopes, pairedAt };
    }
  }
  throw new Error("Could not reach your Mac. Check Tailscale and reload.");
};

export const saveCredentials = async (_credentials: Credentials): Promise<void> => {};

export const clearCredentials = async (_alreadyRevoked = false): Promise<boolean> => unpair(origin(), null);
