import type { Alert } from "@vitals/contracts";

import type { PermissionState } from "./permission.ts";

export const notificationPermission = async (): Promise<PermissionState> => {
  if (!("Notification" in globalThis)) return "unsupported";
  return Notification.permission === "default" ? "prompt" : Notification.permission;
};

export const prepareNotifications = async (): Promise<boolean> => (await notificationPermission()) === "granted";

export const requestNotifications = async (): Promise<boolean> =>
  "Notification" in globalThis && (await Notification.requestPermission()) === "granted";

export const notifyAlert = async (alert: Alert): Promise<void> => {
  if (!("Notification" in globalThis) || Notification.permission !== "granted") return;
  const notification = new Notification(alert.severity === "critical" ? "Mac under heavy pressure" : "Mac under pressure", {
    body: `${alert.summary}. ${alert.plan.summary}.`,
    tag: alert.id,
  });
  notification.addEventListener("click", () => globalThis.focus());
};

export const onCalmAction = (_handler: () => void): (() => void) => () => {};
