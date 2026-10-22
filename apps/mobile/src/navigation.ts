import type { NavigatorScreenParams } from "@react-navigation/native";
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
