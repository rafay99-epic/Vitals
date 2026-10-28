import * as Sentry from "@sentry/react-native";
import { Store } from "@vitals/client-runtime";
import { channel } from "@vitals/app/lib/variant.ts";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import { clientLog } from "@vitals/app/state/clientLog.ts";
import type { ActivityLevel } from "@vitals/contracts";
import * as SecureStore from "expo-secure-store";

import { scrubBreadcrumb, scrubEvent, scrubLog, scrubRecord } from "./scrub.ts";

/** Public by design: a DSN only lets an app send events to the Vitals Remote project. */
const DSN = "https://5be678c5d702791317b48ef1ba197a04@o4512219615920128.ingest.us.sentry.io/4512333352861696";
const KEY = "vitals.remote.errorReports";

const LOG: Record<ActivityLevel, (message: string, attributes: Record<string, unknown>) => void> = {
  debug: () => undefined,
  info: (message, attributes) => Sentry.logger.info(message, attributes),
  warn: (message, attributes) => Sentry.logger.warn(message, attributes),
  error: (message, attributes) => Sentry.logger.error(message, attributes),
};

/** Read synchronously, so a crash during launch already honors an opt-out. */
const saved = (): boolean => {
  try {
    return SecureStore.getItem(KEY, KEYCHAIN_OPTIONS) !== "0";
  } catch {
    return true;
  }
};

/** "Send error reports": on unless turned off in Settings → Help. */
export const errorReports = new Store<boolean>(saved());

let started = false;

const start = (): void => {
  if (started || __DEV__) return;
  started = true;
  Sentry.init({
    dsn: DSN,
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

/**
 * Sentry gets crashes, uncaught errors and the phone's log lines (connection changes, failures).
 * Uncaught errors are Sentry's own; `client.app.fault` would only repeat them. Off in `expo start`
 * dev mode, and entirely when the owner turned reports off. Starts on import: index.ts loads this
 * first, so errors while the app's modules load are caught too.
 */
if (errorReports.get()) start();
clientLog.listen((event) => {
  if (started && errorReports.get() && event.kind !== "client.app.fault") LOG[event.level](event.kind, scrubRecord(event.data));
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
