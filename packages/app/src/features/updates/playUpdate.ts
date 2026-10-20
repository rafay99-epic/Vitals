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

const NOT_FROM_PLAY = /\(-10\)|not owned/i;

const stateFrom = (result: InAppUpdates.UpdateInfo): PlayState => {
  const version = result.storeVersion ?? "new";
  if (result.updateInProgress === true) return { _tag: "Downloading", version };
  return result.updateAvailable ? { _tag: "Available", version } : { _tag: "Current" };
};

const failureFrom = (error: unknown): PlayState => ({
  _tag: "Unavailable",
  reason: error instanceof Error && NOT_FROM_PLAY.test(error.message) ? "not installed from Google Play" : "could not reach Google Play",
});

export const checkPlay = async (): Promise<PlayState> => {
  if (!playSupported) return playState.get();
  const next = await InAppUpdates.checkForUpdate().then(stateFrom).catch(failureFrom);
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
  const started = await InAppUpdates.startUpdate(false).catch(() => false);
  if (!started) return false;
  playPrompt.set(null);
  playState.set({ _tag: "Downloading", version: current.version });
  return true;
};
