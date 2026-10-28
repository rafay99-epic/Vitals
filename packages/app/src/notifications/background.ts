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
import { dismissAlert, notificationPermission, notifyAlert } from "./alerts";

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

/// Makes the notification shade match `open`, the Mac's full list of open alerts: each alert is
/// posted once, and taken down when it is no longer open. `quiet` while the app is on screen,
/// where the alert already shows. Used live and by the background check.
export const syncAlerts = (open: ReadonlyArray<Alert>, quiet: boolean): Promise<void> =>
  serialized(async () => {
    // Until notifications are allowed nothing reaches the shade, so leave every alert unposted.
    if ((await notificationPermission()) !== "granted") return;
    const notified = await readNotified();
    const seen = new Set(notified);
    const openIds = new Set<string>(open.map((alert) => alert.id));
    const fresh = [...new Map(open.filter((alert) => !seen.has(alert.id)).map((alert) => [alert.id, alert])).values()];
    const cleared = notified.filter((id) => !openIds.has(id));
    await Promise.all([...fresh.map((alert) => notifyAlert(alert, quiet)), ...cleared.map((id) => dismissAlert(id))]);
    if (fresh.length === 0 && cleared.length === 0) return;
    const kept = notified.filter((id) => openIds.has(id));
    await SecureStore.setItemAsync(STATE_KEY, JSON.stringify([...kept, ...fresh.map((alert) => alert.id)].slice(-NOTIFIED_KEPT)), KEYCHAIN_OPTIONS);
  });

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
  await syncAlerts(open, false);
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
