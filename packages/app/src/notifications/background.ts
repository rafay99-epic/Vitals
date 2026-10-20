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
const NOTIFIED_KEPT = 50;

const AlertWatchState = Schema.Struct({ seq: Schema.Int, notified: Schema.Array(Schema.String) });
type AlertWatchState = typeof AlertWatchState.Type;
const decodeState = Schema.decodeUnknownOption(Schema.fromJsonString(AlertWatchState));

const readState = async (): Promise<AlertWatchState | null> => {
  const raw = await SecureStore.getItemAsync(STATE_KEY, KEYCHAIN_OPTIONS);
  if (raw === null) return null;
  const decoded = decodeState(raw);
  return decoded._tag === "Some" ? decoded.value : null;
};

let queue: Promise<unknown> = Promise.resolve();
const serialized = <A>(task: () => Promise<A>): Promise<A> => {
  const next = queue.then(task, task);
  queue = next.catch(() => undefined);
  return next;
};

const update = (change: (state: AlertWatchState | null) => AlertWatchState) =>
  serialized(async () => {
    const next = change(await readState());
    await SecureStore.setItemAsync(STATE_KEY, JSON.stringify(next), KEYCHAIN_OPTIONS);
    return next;
  });

export const rememberAlertSeq = async (seq: number): Promise<void> => {
  await update((state) => (state === null ? { seq, notified: [] } : { ...state, seq: Math.max(state.seq, seq) }));
};

export const notifyOnce = async (alert: Alert): Promise<void> => {
  let fresh = false;
  await update((state) => {
    const notified = state?.notified ?? [];
    fresh = !notified.includes(alert.id);
    return { seq: state?.seq ?? 0, notified: fresh ? [...notified, alert.id].slice(-NOTIFIED_KEPT) : notified };
  });
  if (fresh) await notifyAlert(alert);
};

const checkAlerts = async (): Promise<void> => {
  const credentials = await loadCredentials();
  if (credentials === null) return;
  const state = await readState();
  const open = await fetchOpenAlerts(credentials.baseUrl, credentials.token, state?.seq ?? 0);
  if (open === null) throw new Error("Mac unreachable");
  if (state === null) return rememberAlertSeq(open.lastSeq);
  const restarted = open.lastSeq < state.seq;
  const alerts = restarted ? ((await fetchOpenAlerts(credentials.baseUrl, credentials.token, 0))?.alerts ?? []) : open.alerts;
  for (const alert of alerts) await notifyOnce(alert);
  await update((current) => ({ seq: open.lastSeq, notified: current?.notified ?? [] }));
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
