import type { Drop } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import * as Notifications from "expo-notifications";
import { Platform } from "react-native";

import { dropLabel, senderOf } from "../state/drops.ts";

export const TRANSFER_CATEGORY = "transfer";
export const TRANSFER_CHANNEL = "transfers";
const ACCEPT = "accept";
const DECLINE = "decline";

export type TransferAnswer = "accept" | "decline" | "open" | "arrived";

/**
 * Accept and Decline on a transfer notification. iOS only receives with Vitals open and can't be
 * relied on to run it in the background, so there both open the app; Android answers in place.
 */
export const transferActions: ReadonlyArray<Notifications.NotificationAction> = [
  { identifier: ACCEPT, buttonTitle: "Accept", options: { opensAppToForeground: true } },
  { identifier: DECLINE, buttonTitle: "Decline", options: { opensAppToForeground: Platform.OS === "ios", isDestructive: true } },
];

const idOf = (dropId: string): string => `transfer:${dropId}`;
const ARRIVED = "arrived";

/** Puts a transfer that is waiting for an answer in the notification shade. `quiet` while the app is on screen, where it asks too. */
export const notifyTransfer = async (drop: Drop, quiet: boolean): Promise<void> => {
  const names = drop.files
    .slice(0, 2)
    .map((file) => file.name)
    .join(", ");
  const more = drop.files.length > 2 ? ` and ${String(drop.files.length - 2)} more` : "";
  await Notifications.scheduleNotificationAsync({
    identifier: idOf(drop.id),
    content: {
      title: `${senderOf(drop)} wants to send ${dropLabel(drop)}`,
      body: `${names}${more} · ${formatBytes(drop.bytes)}`,
      categoryIdentifier: TRANSFER_CATEGORY,
      data: { dropId: drop.id, quiet },
    },
    trigger: Platform.OS === "android" ? { channelId: TRANSFER_CHANNEL } : null,
  });
};

export const dismissTransfer = (dropId: string): Promise<void> => Notifications.dismissNotificationAsync(idOf(dropId));

/** Says a drop finished arriving and where it went. Tapping it opens what came. `quiet` while the app is on screen. */
export const notifyArrival = async (drop: Drop, where: string, quiet: boolean): Promise<void> => {
  await Notifications.scheduleNotificationAsync({
    identifier: `${ARRIVED}:${drop.id}`,
    content: {
      title: `${dropLabel(drop)} arrived from ${drop.from._tag === "Mac" ? "your Mac" : drop.from.name}`,
      body: `In ${where}`,
      data: { dropId: drop.id, kind: ARRIVED, quiet },
    },
    trigger: Platform.OS === "android" ? { channelId: TRANSFER_CHANNEL } : null,
  });
};

const ANSWERS: Readonly<Record<string, TransferAnswer>> = { [ACCEPT]: "accept", [DECLINE]: "decline", [Notifications.DEFAULT_ACTION_IDENTIFIER]: "open" };

/** Calls `handler` for each answer given on a transfer notification, or a tap on an arrival, including the one that opened the app. */
export const onTransferAnswer = (handler: (dropId: string, answer: TransferAnswer) => void): (() => void) => {
  const handle = (response: Notifications.NotificationResponse) => {
    const content = response.notification.request.content;
    const dropId = content.data?.["dropId"];
    const arrived = content.data?.["kind"] === ARRIVED;
    const answer = arrived ? "arrived" : ANSWERS[response.actionIdentifier];
    if ((!arrived && content.categoryIdentifier !== TRANSFER_CATEGORY) || typeof dropId !== "string" || answer === undefined) return;
    void Notifications.clearLastNotificationResponseAsync();
    handler(dropId, answer);
  };
  const launchedBy = Notifications.getLastNotificationResponse();
  if (launchedBy !== null) handle(launchedBy);
  const subscription = Notifications.addNotificationResponseReceivedListener(handle);
  return () => subscription.remove();
};
