import { Store } from "@vitals/client-runtime";
import * as SecureStore from "expo-secure-store";
import * as Updates from "expo-updates";

import { color } from "../ui/tokens.ts";

/**
 * Over-the-air updates that never block. A new bundle downloads quietly and applies on the
 * next cold start; Settings > Updates offers "Restart now" for the impatient.
 */
export type UpdateState =
  | { readonly _tag: "Off" }
  | { readonly _tag: "Idle" }
  | { readonly _tag: "Checking" }
  | { readonly _tag: "Downloading" }
  | { readonly _tag: "Ready"; readonly publishedAt: number | null }
  | { readonly _tag: "Current"; readonly at: number }
  | { readonly _tag: "Failed"; readonly at: number; readonly reason: string };

const updatesEnabled = !__DEV__ && Updates.isEnabled;

export const updateState = new Store<UpdateState>(updatesEnabled ? { _tag: "Idle" } : { _tag: "Off" });

const RECHECK_MS = 30 * 60_000;
let running: Promise<void> | null = null;
let lastCheck = 0;

const publishedAt = (manifest: Updates.Manifest | undefined): number | null => {
  const created = manifest !== undefined && "createdAt" in manifest ? Date.parse(String(manifest.createdAt)) : Number.NaN;
  return Number.isFinite(created) ? created : null;
};

const NO_CHANNEL = /no channel named/i;

const reasonOf = (error: unknown): string => (error instanceof Error ? error.message : "Could not reach the update server");

const run = async (): Promise<void> => {
  updateState.set({ _tag: "Checking" });
  try {
    const check = await Updates.checkForUpdateAsync();
    if (!check.isAvailable && !check.isRollBackToEmbedded) {
      updateState.set({ _tag: "Current", at: Date.now() });
      return;
    }
    updateState.set({ _tag: "Downloading" });
    const fetched = await Updates.fetchUpdateAsync();
    updateState.set(fetched.isNew || fetched.isRollBackToEmbedded ? { _tag: "Ready", publishedAt: publishedAt(check.manifest) } : { _tag: "Current", at: Date.now() });
  } catch (error) {
    // A channel nobody has published to yet (a fresh Nightly) has nothing newer than the built-in code.
    if (error instanceof Error && NO_CHANNEL.test(error.message)) return updateState.set({ _tag: "Current", at: Date.now() });
    updateState.set({ _tag: "Failed", at: Date.now(), reason: reasonOf(error) });
  }
};

/** Checks in the background. `force` skips the 30 minute throttle (the Check now button). */
export const checkForUpdate = (force = false): Promise<void> => {
  if (!updatesEnabled || updateState.get()._tag === "Ready") return Promise.resolve();
  if (!force && Date.now() - lastCheck < RECHECK_MS) return Promise.resolve();
  lastCheck = Date.now();
  running ??= run().finally(() => {
    running = null;
  });
  return running;
};

/** Restarts into the downloaded update. Only offered when one is ready. */
export const restartIntoUpdate = (): Promise<void> =>
  Updates.reloadAsync({ reloadScreenOptions: { backgroundColor: color.bg, fade: true, spinner: { enabled: false } } }).catch((error: unknown) => {
    // Settings then shows the reason and offers Check now, instead of sitting on Ready after a reload that never happened.
    updateState.set({ _tag: "Failed", at: Date.now(), reason: reasonOf(error) });
  });

const SEEN_KEY = "vitals.remote.update-seen";

/**
 * True when this launch runs a different update than the last launch did, so the app can
 * confirm "updated" once. False on the very first launch.
 */
export const launchedNewUpdate = async (): Promise<boolean> => {
  const current = Updates.updateId ?? "built-in";
  const seen = await SecureStore.getItemAsync(SEEN_KEY).catch(() => null);
  await SecureStore.setItemAsync(SEEN_KEY, current).catch(() => undefined);
  return seen !== null && seen !== current;
};
