import { createNavigationContainerRef, type NavigatorScreenParams } from "@react-navigation/native";
import type { FsSource } from "@vitals/app/state/files.ts";
import type { FsRecentKind } from "@vitals/contracts";
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

/** Received and sent files, e.g. from a "file landed" toast. */
export const openTransfers = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("Control", { screen: "Transfers", initial: false });
};

/** Opens Settings > Updates with Settings underneath, so Back works. */
export const openUpdates = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("SettingsTab", { screen: "Updates", initial: false });
};
