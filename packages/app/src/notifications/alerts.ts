import type { Alert } from "@vitals/contracts";
import Constants from "expo-constants";
import * as Notifications from "expo-notifications";
import { Platform } from "react-native";

const CATEGORY = "pressure";
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
    await Notifications.setNotificationChannelAsync("pressure", {
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

export const notifyAlert = async (alert: Alert): Promise<void> => {
  await Notifications.scheduleNotificationAsync({
    content: {
      title: alert.severity === "critical" ? "Mac under heavy pressure" : "Mac under pressure",
      body: `${alert.summary}. ${alert.plan.summary}.`,
      categoryIdentifier: CATEGORY,
      data: { alertId: alert.id },
    },
    trigger: Platform.OS === "android" ? { channelId: "pressure" } : null,
  });
};

export const onCalmAction = (handler: () => void): (() => void) => {
  const subscription = Notifications.addNotificationResponseReceivedListener((response) => {
    if (response.actionIdentifier === CALM_ACTION) handler();
  });
  return () => subscription.remove();
};

export const pushToken = async (): Promise<string | null> => {
  const projectId: unknown = Constants.expoConfig?.extra?.["eas"]?.projectId;
  if (typeof projectId !== "string") return null;
  try {
    return (await Notifications.getExpoPushTokenAsync({ projectId })).data;
  } catch {
    return null;
  }
};
