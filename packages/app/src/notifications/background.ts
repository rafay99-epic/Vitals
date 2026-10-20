import { fetchOpenAlerts } from "@vitals/client-runtime";
import type { Alert } from "@vitals/contracts";
import * as Schema from "effect/Schema";
import * as BackgroundTask from "expo-background-task";
import * as SecureStore from "expo-secure-store";
import * as TaskManager from "expo-task-manager";

import { KEYCHAIN_OPTIONS, loadCredentials } from "../persistence/credentials";
import { notifyAlert } from "./alerts";

const TASK = "vitals.alerts";
const STATE_KEY = "vitals.remote.alerts";
const INTERVAL_MINUTES = 15;
const NOTIFIED_KEPT = 500;

const Notified = Schema.Array(Schema.String);
const decodeNotified = Schema.decodeUnknownOption(Schema.fromJsonString(Notified));

let queue: Promise<unknown> = Promise.resolve();
const serialized = <A>(task: () => Promise<A>): Promise<A> => {
  const next = queue.then(task, task);
  queue = next.catch(() => undefined);
  return next;
};

const readNotified = async (): Promise<ReadonlyArray<string>> => {
  const raw = await SecureStore.getItemAsync(STATE_KEY, KEYCHAIN_OPTIONS);
  const decoded = raw === null ? null : decodeNotified(raw);
  return decoded?._tag === "Some" ? decoded.value : [];
};

const deliver = (alerts: ReadonlyArray<Alert>, show: boolean, openNow: ReadonlyArray<Alert> | null = null) =>
  serialized(async () => {
    const notified = await readNotified();
    const delivered: Array<string> = [];
    for (const alert of alerts) {
      if (notified.includes(alert.id) || delivered.includes(alert.id)) continue;
      if (show) await notifyAlert(alert);
      delivered.push(alert.id);
    }
    const stillOpen = openNow === null ? notified : notified.filter((id) => openNow.some((alert) => alert.id === id));
    if (delivered.length === 0 && stillOpen.length === notified.length) return;
    await SecureStore.setItemAsync(STATE_KEY, JSON.stringify([...stillOpen, ...delivered].slice(-NOTIFIED_KEPT)), KEYCHAIN_OPTIONS);
  });

export const markAlertsSeen = (alerts: ReadonlyArray<Alert>): Promise<void> => deliver(alerts, false);

export const notifyOnce = (alert: Alert): Promise<void> => deliver([alert], true);

const checkAlerts = async (): Promise<void> => {
  const credentials = await loadCredentials();
  if (credentials === null) return;
  const open = await fetchOpenAlerts(credentials.baseUrl, credentials.token, 0);
  if (open === null) throw new Error("Mac unreachable");
  await deliver(open.alerts, true, open.alerts);
};

TaskManager.defineTask(TASK, async () => {
  try {
    await checkAlerts();
    return BackgroundTask.BackgroundTaskResult.Success;
  } catch {
    return BackgroundTask.BackgroundTaskResult.Failed;
  }
});

export const startAlertWatch = async (): Promise<boolean> => {
  if ((await BackgroundTask.getStatusAsync()) !== BackgroundTask.BackgroundTaskStatus.Available) return false;
  if (!(await TaskManager.isTaskRegisteredAsync(TASK))) {
    await BackgroundTask.registerTaskAsync(TASK, { minimumInterval: INTERVAL_MINUTES });
  }
  return true;
};

export const stopAlertWatch = async (): Promise<void> => {
  if (await TaskManager.isTaskRegisteredAsync(TASK)) await BackgroundTask.unregisterTaskAsync(TASK);
  await serialized(() => SecureStore.deleteItemAsync(STATE_KEY, KEYCHAIN_OPTIONS));
};
