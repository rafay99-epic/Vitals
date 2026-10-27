import { Store } from "@vitals/client-runtime";
import { channel } from "@vitals/app/lib/variant.ts";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import * as Network from "expo-network";
import * as SecureStore from "expo-secure-store";
import * as Updates from "expo-updates";

import { color } from "../ui/tokens.ts";
import { downloadsNow, notesOf, type QuickUpdates, type UpdateState } from "./updateModel.ts";

/**
 * Over-the-air updates that never block. A found update downloads in the background (on the
 * network the user allows) and applies on the next cold start; the update sheet and Settings >
 * Updates offer "Restart now" for the impatient.
 */
const updatesEnabled = !__DEV__ && Updates.isEnabled;

export const updateState = new Store<UpdateState>(updatesEnabled ? { _tag: "Idle" } : { _tag: "Off" });

/** True when the last quick update failed to start and the app went back to the one before. */
export const rolledBack = Updates.isEmergencyLaunch;

/** What this launch runs, for the Updates page. */
export const thisLaunch = {
  notes: notesOf(Updates.manifest),
  createdAt: Updates.isEmbeddedLaunch ? null : (Updates.createdAt?.getTime() ?? null),
  id: Updates.isEmbeddedLaunch ? null : (Updates.updateId?.slice(0, 8) ?? null),
};

const CHOICE_KEY = "vitals.remote.quick-updates";

/** Dev builds take updates on any network, so testing never waits for Wi-Fi. */
export const quickUpdates = new Store<QuickUpdates>(channel === "dev" ? "any" : "wifi");
let chosen = false;

void SecureStore.getItemAsync(CHOICE_KEY, KEYCHAIN_OPTIONS)
  .then((value) => {
    if (!chosen && (value === "wifi" || value === "any" || value === "ask")) quickUpdates.set(value);
  })
  .catch(() => undefined);

export const setQuickUpdates = (choice: QuickUpdates): void => {
  chosen = true;
  quickUpdates.set(choice);
  void SecureStore.setItemAsync(CHOICE_KEY, choice, KEYCHAIN_OPTIONS).catch(() => undefined);
};

const RECHECK_MS = 30 * 60_000;
let inFlight: Promise<void> | null = null;
let lastCheck = 0;

const NO_CHANNEL = /no channel named/i;

const reasonOf = (error: unknown): string => (error instanceof Error ? error.message : "Could not reach the update server");

const networkNow = async (): Promise<"wifi" | "cellular" | "other"> => {
  const state = await Network.getNetworkStateAsync().catch(() => null);
  if (state?.type === Network.NetworkStateType.CELLULAR) return "cellular";
  return state?.type === Network.NetworkStateType.WIFI || state?.type === Network.NetworkStateType.ETHERNET ? "wifi" : "other";
};

/** Downloads a found update. Also the Download button when the user asked to be asked first. */
export const downloadUpdate = async (id: string, notes: string): Promise<void> => {
  updateState.set({ _tag: "Downloading", progress: 0 });
  try {
    const fetched = await Updates.fetchUpdateAsync();
    updateState.set(fetched.isNew || fetched.isRollBackToEmbedded ? { _tag: "Ready", id, notes } : { _tag: "Current", at: Date.now() });
  } catch (error) {
    updateState.set({ _tag: "Failed", at: Date.now(), reason: reasonOf(error), step: "download" });
  }
};

const run = async (): Promise<void> => {
  updateState.set({ _tag: "Checking" });
  try {
    const check = await Updates.checkForUpdateAsync();
    if (!check.isAvailable && !check.isRollBackToEmbedded) {
      updateState.set({ _tag: "Current", at: Date.now() });
      return;
    }
    const id = check.manifest?.id ?? "built-in";
    const notes = notesOf(check.manifest);
    if (!downloadsNow(quickUpdates.get(), await networkNow())) return updateState.set({ _tag: "Found", id, notes });
    await downloadUpdate(id, notes);
  } catch (error) {
    // A channel nobody has published to yet (a fresh Nightly) has nothing newer than the built-in code.
    if (error instanceof Error && NO_CHANNEL.test(error.message)) return updateState.set({ _tag: "Current", at: Date.now() });
    updateState.set({ _tag: "Failed", at: Date.now(), reason: reasonOf(error), step: "check" });
  }
};

// Real download progress, 0 to 1, while a download runs.
Updates.addUpdatesStateChangeListener(({ context }) => {
  const state = updateState.get();
  if (state._tag === "Downloading" && context.isDownloading && context.downloadProgress !== undefined) updateState.set({ _tag: "Downloading", progress: context.downloadProgress });
});

const settled = (state: UpdateState): boolean => state._tag === "Ready" || state._tag === "Found" || state._tag === "Downloading";

/** Checks in the background. `force` skips the 30 minute throttle (the Check button). */
export const checkForUpdate = (force = false): Promise<void> => {
  if (!updatesEnabled || settled(updateState.get())) return Promise.resolve();
  if (!force && Date.now() - lastCheck < RECHECK_MS) return Promise.resolve();
  lastCheck = Date.now();
  inFlight ??= run().finally(() => {
    inFlight = null;
  });
  return inFlight;
};

/** Restarts into the downloaded update. Only offered when one is ready. */
export const restartIntoUpdate = (): Promise<void> =>
  Updates.reloadAsync({ reloadScreenOptions: { backgroundColor: color.bg, fade: true, spinner: { enabled: false } } }).catch((error: unknown) => {
    // The page then shows the reason and offers Check, instead of sitting on Ready after a reload that never happened.
    updateState.set({ _tag: "Failed", at: Date.now(), reason: reasonOf(error), step: "download" });
  });

const SEEN_KEY = "vitals.remote.update-seen";

/**
 * True when this launch runs a different update than the last launch did, so the app can
 * say "updated" once. False on the very first launch.
 */
export const launchedNewUpdate = async (): Promise<boolean> => {
  const current = Updates.updateId ?? "built-in";
  const seen = await SecureStore.getItemAsync(SEEN_KEY).catch(() => null);
  await SecureStore.setItemAsync(SEEN_KEY, current).catch(() => undefined);
  return seen !== null && seen !== current;
};
