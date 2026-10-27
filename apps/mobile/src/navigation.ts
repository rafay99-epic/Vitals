import { createNavigationContainerRef, type NavigatorScreenParams } from "@react-navigation/native";
import type { DeviceId, FsRecentKind } from "@vitals/contracts";
import type { Channel } from "@vitals/ui";

export type HomeStackParams = {
  Home: undefined;
  Channel: { readonly channel: Channel };
};

export type ControlStackParams = {
  Control: undefined;
  Clipboard: undefined;
  Files: undefined;
  Folder: { readonly path: string; readonly title: string; readonly device?: DeviceId; readonly deviceName?: string };
  /** "See all" for one kind on a device page. No device means the Mac. */
  Recent: { readonly kind: FsRecentKind; readonly device?: DeviceId; readonly deviceName?: string };
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

/** Opens Settings > Updates with Settings underneath, so Back works. */
export const openUpdates = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("SettingsTab", { screen: "Updates", initial: false });
};
