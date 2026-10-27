import { createNavigationContainerRef, type NavigatorScreenParams, StackActions } from "@react-navigation/native";
import type { FsSource } from "@vitals/app/state/files.ts";
import type { FsEntry, FsRecentKind } from "@vitals/contracts";
import type { Channel } from "@vitals/ui";

export type HomeStackParams = {
  Home: undefined;
  Channel: { readonly channel: Channel };
};

export type ControlStackParams = {
  Control: undefined;
  Clipboard: undefined;
  Files: undefined;
  /** `trail` is the folder names from the device's root down to this one. */
  Folder: { readonly path: string; readonly source: FsSource; readonly trail: ReadonlyArray<string> };
  /** Everything of one kind on a device, newest first. "images" is screenshots and photos together. */
  Recent: { readonly kind: FsRecentKind | "images"; readonly source: FsSource };
  /** One file, viewed here. `parent` names the screen Back goes to. `local` is an already-cached copy (a file unpacked from a zip), which can't be transferred. */
  Preview: { readonly entry: FsEntry; readonly source: FsSource; readonly parent: string; readonly local?: string };
  Transfers: undefined;
  Terminal: undefined;
};

export type SettingsStackParams = {
  Settings: undefined;
  Connection: undefined;
  Notifications: undefined;
  Updates: undefined;
  Phone: undefined;
  Help: undefined;
  Diagnostics: undefined;
};

export type TabParams = {
  HomeTab: NavigatorScreenParams<HomeStackParams> | undefined;
  Apps: undefined;
  Control: NavigatorScreenParams<ControlStackParams> | undefined;
  Alerts: undefined;
  SettingsTab: NavigatorScreenParams<SettingsStackParams> | undefined;
};

/** Lets code outside screens (toasts, notifications) move the user to a screen. */
export const navigationRef = createNavigationContainerRef<TabParams>();

/** Opens Control > Clipboard with Control underneath, e.g. after sharing something into Vitals. */
export const openClipboard = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("Control", { screen: "Clipboard", initial: false });
};

export const openFiles = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("Control", { screen: "Files", initial: false });
};

/** Pushes a file's preview onto the Files stack, e.g. from a file's sheet. */
export const openPreview = (params: ControlStackParams["Preview"]): void => {
  if (navigationRef.isReady()) navigationRef.dispatch(StackActions.push("Preview", params));
};

/** Received and sent files, e.g. from a "file landed" toast. */
export const openTransfers = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("Control", { screen: "Transfers", initial: false });
};

/** Opens Settings > Updates with Settings underneath, so Back works. */
export const openUpdates = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("SettingsTab", { screen: "Updates", initial: false });
};
