import type { Alert } from "@vitals/contracts";

export const prepareNotifications = async (): Promise<boolean> => {
  if (!("Notification" in globalThis)) return false;
  if (Notification.permission === "granted") return true;
  if (Notification.permission === "denied") return false;
  return (await Notification.requestPermission()) === "granted";
};

export const notifyAlert = async (alert: Alert): Promise<void> => {
  if (!("Notification" in globalThis) || Notification.permission !== "granted") return;
  const notification = new Notification(alert.severity === "critical" ? "Mac under heavy pressure" : "Mac under pressure", {
    body: `${alert.summary}. ${alert.plan.summary}.`,
    tag: alert.id,
  });
  notification.addEventListener("click", () => globalThis.focus());
};

export const onCalmAction = (_handler: () => void): (() => void) => () => {};

export const pushToken = async (): Promise<string | null> => null;
