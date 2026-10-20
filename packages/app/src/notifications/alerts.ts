import type { Alert } from "@vitals/contracts";
import * as Notifications from "expo-notifications";
import { Platform } from "react-native";

import type { PermissionState } from "./permission.ts";

const CATEGORY = "pressure";
const CHANNEL = "pressure";
const CALM_ACTION = "calm";

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

export const prepareNotifications = async (): Promise<boolean> => {
  if (Platform.OS === "android") {
    await Notifications.setNotificationChannelAsync(CHANNEL, {
      name: "Mac pressure",
      importance: Notifications.AndroidImportance.HIGH,
    });
  }
  await Notifications.setNotificationCategoryAsync(CATEGORY, [
    { identifier: CALM_ACTION, buttonTitle: "Calm down", options: { opensAppToForeground: true } },
  ]);
  const current = await Notifications.getPermissionsAsync();
  if (current.granted) return true;
  return (await Notifications.requestPermissionsAsync()).granted;
};

export const notificationPermission = async (): Promise<PermissionState> => {
  const current = await Notifications.getPermissionsAsync();
  return current.granted ? "granted" : current.canAskAgain ? "prompt" : "denied";
};

export const requestNotifications = async (): Promise<boolean> => (await Notifications.requestPermissionsAsync()).granted;

export const notifyAlert = async (alert: Alert): Promise<void> => {
  await Notifications.scheduleNotificationAsync({
    identifier: alert.id,
    content: {
      title: alert.severity === "critical" ? "Mac under heavy pressure" : "Mac under pressure",
      body: `${alert.summary}. ${alert.plan.summary}.`,
      categoryIdentifier: CATEGORY,
      data: { alertId: alert.id },
    },
    trigger: Platform.OS === "android" ? { channelId: CHANNEL } : null,
  });
};

export const forgetCalmAction = (): Promise<void> => Notifications.clearLastNotificationResponseAsync();

export const onCalmAction = (handler: () => void): (() => void) => {
  const handle = (response: Notifications.NotificationResponse) => {
    if (response.actionIdentifier !== CALM_ACTION) return;
    void Notifications.clearLastNotificationResponseAsync();
    handler();
  };
  const launchedBy = Notifications.getLastNotificationResponse();
  if (launchedBy !== null) handle(launchedBy);
  const subscription = Notifications.addNotificationResponseReceivedListener(handle);
  return () => subscription.remove();
};
