import { Store } from "@vitals/client-runtime";
import * as InAppUpdates from "expo-in-app-updates";
import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

import { KEYCHAIN_OPTIONS } from "../../persistence/credentials";

export type PlayState =
  | { readonly _tag: "Unchecked" }
  | { readonly _tag: "Current" }
  | { readonly _tag: "Available"; readonly version: string }
  | { readonly _tag: "Downloading"; readonly version: string }
  | { readonly _tag: "Unavailable"; readonly reason: string };

const DISMISSED_KEY = "vitals.remote.play-dismissed";

export const playSupported = Platform.OS === "android";

export const playState = new Store<PlayState>(playSupported ? { _tag: "Unchecked" } : { _tag: "Unavailable", reason: "Google Play is Android only" });

export const playPrompt = new Store<string | null>(null);

const stateFrom = (result: Awaited<ReturnType<typeof InAppUpdates.checkForUpdate>>): PlayState => {
  if (result.updateInProgress === true) return { _tag: "Downloading", version: result.storeVersion };
  return result.updateAvailable ? { _tag: "Available", version: result.storeVersion } : { _tag: "Current" };
};

export const checkPlay = async (): Promise<PlayState> => {
  if (!playSupported) return playState.get();
  const next = await InAppUpdates.checkForUpdate()
    .then(stateFrom)
    .catch((): PlayState => ({ _tag: "Unavailable", reason: "not installed from Google Play" }));
  playState.set(next);
  return next;
};

export const promptPlayOnLaunch = async (): Promise<void> => {
  const next = await checkPlay();
  if (next._tag !== "Available") return;
  const dismissed = await SecureStore.getItemAsync(DISMISSED_KEY, KEYCHAIN_OPTIONS).catch(() => null);
  if (dismissed !== next.version) playPrompt.set(next.version);
};

export const dismissPlay = (): void => {
  const version = playPrompt.get();
  playPrompt.set(null);
  if (version !== null) void SecureStore.setItemAsync(DISMISSED_KEY, version, KEYCHAIN_OPTIONS).catch(() => undefined);
};

export const startPlayUpdate = async (): Promise<boolean> => {
  const current = playState.get();
  if (current._tag !== "Available") return false;
  playPrompt.set(null);
  const started = await InAppUpdates.startUpdate(false).catch(() => false);
  if (started) playState.set({ _tag: "Downloading", version: current.version });
  return started;
};
