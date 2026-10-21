import { createConnection, fetchOpenAlerts } from "@vitals/client-runtime";
import type { Alert } from "@vitals/contracts";
import * as Schema from "effect/Schema";
import * as BackgroundTask from "expo-background-task";
import * as SecureStore from "expo-secure-store";
import * as TaskManager from "expo-task-manager";

import { KEYCHAIN_OPTIONS, loadCredentials } from "../persistence/credentials";
import type { Credentials } from "../persistence/credentialsSchema.ts";
import { loadDeviceKey } from "../persistence/deviceKey";
import { CLIENT_VERSION, routesOf } from "../state/remote.ts";
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
    const seen = new Set(notified);
    const fresh = [...new Map(alerts.filter((alert) => !seen.has(alert.id)).map((alert) => [alert.id, alert])).values()];
    if (show) await Promise.all(fresh.map((alert) => notifyAlert(alert)));
    const delivered = fresh.map((alert) => alert.id);
    const open = openNow === null ? null : new Set<string>(openNow.map((alert) => alert.id));
    const stillOpen = open === null ? notified : notified.filter((id) => open.has(id));
    if (delivered.length === 0 && stillOpen.length === notified.length) return;
    await SecureStore.setItemAsync(STATE_KEY, JSON.stringify([...stillOpen, ...delivered].slice(-NOTIFIED_KEPT)), KEYCHAIN_OPTIONS);
  });

export const markAlertsSeen = (alerts: ReadonlyArray<Alert>): Promise<void> => deliver(alerts, false);

export const notifyOnce = (alert: Alert): Promise<void> => deliver([alert], true);

const WIFI_TIMEOUT_MS = 10_000;

const wifiSocket = (url: string) => {
  const socket = new WebSocket(url);
  socket.binaryType = "arraybuffer";
  return socket;
};

const alertsOverWifi = async (credentials: Credentials): Promise<ReadonlyArray<Alert> | null> => {
  const macKey = credentials.macKey ?? null;
  const deviceKey = await loadDeviceKey().catch(() => null);
  const routes = routesOf(credentials).filter((route) => route._tag === "Lan");
  if (macKey === null || deviceKey === null || routes.length === 0) return null;
  const connection = createConnection({ routes: () => routes, token: credentials.token, macKey: () => macKey, deviceKey, clientVersion: CLIENT_VERSION, webSocket: wifiSocket });
  return new Promise((resolve) => {
    const finish = (alerts: ReadonlyArray<Alert> | null) => {
      clearTimeout(timer);
      stop();
      connection.dispose();
      resolve(alerts);
    };
    const timer = setTimeout(() => finish(null), WIFI_TIMEOUT_MS);
    const stop = connection.state.subscribe(() => {
      const state = connection.state.get();
      if (state._tag === "Ready") finish(state.hello.alerts);
      if (state._tag === "Backoff" || state._tag === "Revoked") finish(null);
    });
  });
};

const openAlerts = async (credentials: Credentials): Promise<ReadonlyArray<Alert> | null> => {
  const viaTailnet = credentials.baseUrl === null ? null : await fetchOpenAlerts(credentials.baseUrl, credentials.token, 0);
  return viaTailnet?.alerts ?? (await alertsOverWifi(credentials));
};

const checkAlerts = async (): Promise<void> => {
  const credentials = await loadCredentials();
  if (credentials === null) return;
  const open = await openAlerts(credentials);
  if (open === null) throw new Error("Mac unreachable");
  await deliver(open, true, open);
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
