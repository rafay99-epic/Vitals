import * as Sentry from "@sentry/react-native";
import { Store } from "@vitals/client-runtime";
import { channel } from "@vitals/app/lib/variant.ts";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import { clientLog } from "@vitals/app/state/clientLog.ts";
import type { ActivityLevel } from "@vitals/contracts";
import { scrubBreadcrumb, scrubEvent, scrubRecord } from "@vitals/shared";
import * as SecureStore from "expo-secure-store";

import { scrubLog } from "./scrub.ts";

const DSN: Record<typeof channel, string> = {
  stable: "https://5be678c5d702791317b48ef1ba197a04@o4512219615920128.ingest.us.sentry.io/4512333352861696",
  nightly: "https://1f83005752755c77e49b385091138d40@o4512219615920128.ingest.us.sentry.io/4512333983055872",
  dev: "https://1f83005752755c77e49b385091138d40@o4512219615920128.ingest.us.sentry.io/4512333983055872",
};
const KEY = "vitals.remote.errorReports";

const LOG: Record<ActivityLevel, (message: string, attributes: Record<string, unknown>) => void> = {
  debug: () => undefined,
  info: (message, attributes) => Sentry.logger.info(message, attributes),
  warn: (message, attributes) => Sentry.logger.warn(message, attributes),
  error: (message, attributes) => Sentry.logger.error(message, attributes),
};

const saved = (): boolean => {
  try {
    return SecureStore.getItem(KEY, KEYCHAIN_OPTIONS) !== "0";
  } catch {
    return true;
  }
};

export const errorReports = new Store<boolean>(saved());

let started = false;

const start = (): void => {
  if (started || __DEV__) return;
  started = true;
  Sentry.init({
    dsn: DSN[channel],
    environment: channel,
    sendDefaultPii: false,
    attachScreenshot: false,
    attachViewHierarchy: false,
    enableLogs: true,
    logsOrigin: "js",
    enableAutoConsoleLogs: false,
    beforeSend: (event) => (errorReports.get() ? scrubEvent(event) : null),
    beforeBreadcrumb: (crumb) => scrubBreadcrumb(crumb),
    beforeSendLog: (log) => (errorReports.get() ? scrubLog(log) : null),
  });
};

if (errorReports.get()) start();
const PRIVATE_TEXT = new Set(["client.ui.failure"]);

clientLog.listen((event) => {
  if (!started || !errorReports.get() || event.kind === "client.app.fault") return;
  LOG[event.level](event.kind, PRIVATE_TEXT.has(event.kind) ? {} : scrubRecord(event.data));
});

export const setErrorReports = (on: boolean): void => {
  errorReports.set(on);
  void SecureStore.setItemAsync(KEY, on ? "1" : "0", KEYCHAIN_OPTIONS).catch(() => undefined);
  if (on) start();
  else if (started) {
    started = false;
    void Sentry.close();
  }
};
