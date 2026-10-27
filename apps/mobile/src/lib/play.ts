import { Store } from "@vitals/client-runtime";
import { channel } from "@vitals/app/lib/variant.ts";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

import { checkPlayStore, completePlayStore, onPlayStore, playModule, startPlayStore } from "../../modules/vitals-update/index.ts";
import type { PlayState } from "./updateModel.ts";

/** Only Stable is installed from Google Play; Nightly updates from GitHub, Dev is installed by hand. */
export const playSupported = Platform.OS === "android" && channel === "stable" && playModule;

export const playState = new Store<PlayState>(playSupported ? { _tag: "Unchecked" } : { _tag: "Off", reason: "Only the Google Play app updates from Google Play" });

const RECHECK_MS = 30 * 60_000;
let lastCheck = 0;

/** Asks Play whether a newer build exists, at most every 30 minutes unless `force`. */
export const checkPlay = async (force = false): Promise<void> => {
  if (!playSupported || (!force && Date.now() - lastCheck < RECHECK_MS)) return;
  lastCheck = Date.now();
  const facts = await checkPlayStore().catch(() => null);
  const now = playState.get();
  if (facts === null) return playState.set({ _tag: "Off", reason: "Not installed from Google Play" });
  if (facts.download === "downloaded") return playState.set({ _tag: "Downloaded", version: facts.version });
  // Progress events carry a running download; a check in the middle must not reset it.
  if (facts.download === "downloading") return playState.set(now._tag === "Downloading" ? now : { _tag: "Downloading", version: facts.version, progress: 0 });
  playState.set(facts.available && facts.flexible ? { _tag: "Available", version: facts.version } : { _tag: "Current" });
};

/** Opens Play's update screen. Flexible downloads in the background; `immediate` lets Play take over until it's installed. */
export const startPlay = async (immediate = false): Promise<boolean> => {
  const now = playState.get();
  if (now._tag !== "Available" && now._tag !== "Stopped") return false;
  const outcome = await startPlayStore(immediate).catch(() => "failed" as const);
  if (outcome === "accepted" && !immediate) playState.set({ _tag: "Downloading", version: now.version, progress: 0 });
  return outcome === "accepted";
};

/** Installs a downloaded build: the app closes, Android installs it and reopens Vitals. */
export const installPlay = (): void => completePlayStore();

onPlayStore({
  onProgress: ({ progress }) => {
    const now = playState.get();
    if (now._tag === "Available" || now._tag === "Downloading" || now._tag === "Stopped") playState.set({ _tag: "Downloading", version: now.version, progress });
  },
  onDownloaded: () => {
    const now = playState.get();
    if (now._tag === "Available" || now._tag === "Downloading" || now._tag === "Stopped") playState.set({ _tag: "Downloaded", version: now.version });
  },
  onStopped: ({ reason }) => {
    const now = playState.get();
    if (now._tag !== "Downloading") return;
    playState.set(reason === "cancelled" ? { _tag: "Available", version: now.version } : { _tag: "Stopped", version: now.version, reason });
  },
});

const SKIPPED_KEY = "vitals.remote.play-skipped";

/** The Play version the user said Later to. Its sheet stays away until a newer build. */
export const skippedPlay = new Store<number | null>(null);

void SecureStore.getItemAsync(SKIPPED_KEY, KEYCHAIN_OPTIONS)
  .then((value) => value !== null && skippedPlay.set(Number(value) || null))
  .catch(() => undefined);

export const skipPlay = (version: number): void => {
  skippedPlay.set(version);
  void SecureStore.setItemAsync(SKIPPED_KEY, String(version), KEYCHAIN_OPTIONS).catch(() => undefined);
};
