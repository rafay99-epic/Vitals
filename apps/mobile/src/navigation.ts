import { createNavigationContainerRef, type NavigatorScreenParams } from "@react-navigation/native";
import type { Channel } from "@vitals/ui";

export type HomeStackParams = {
  Home: undefined;
  Channel: { readonly channel: Channel };
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
  Control: undefined;
  Alerts: undefined;
  SettingsTab: NavigatorScreenParams<SettingsStackParams> | undefined;
};

/** Lets code outside screens (toasts, notifications) move the user to a screen. */
export const navigationRef = createNavigationContainerRef<TabParams>();

/** Opens Settings > Updates with Settings underneath, so Back works. */
export const openUpdates = (): void => {
  if (navigationRef.isReady()) navigationRef.navigate("SettingsTab", { screen: "Updates", initial: false });
};
