import * as Sentry from "@sentry/bun";
import type { ActivityLevel } from "@vitals/contracts";
import { scrubBreadcrumb, scrubEvent, scrubRecord, scrubText, sentryDsn } from "@vitals/shared";
import * as Cause from "effect/Cause";
import * as Effect from "effect/Effect";
import * as Logger from "effect/Logger";
import type * as LogLevel from "effect/LogLevel";

import type { ActivityEvent } from "../activity/ActivityLog.ts";
import type { Channel } from "../config.ts";

const SENTRY_LEVEL: Partial<Record<LogLevel.LogLevel, "info" | "warn" | "error" | "fatal">> = {
  Info: "info",
  Warn: "warn",
  Error: "error",
  Fatal: "fatal",
};

const ACTIVITY_LEVEL: Record<ActivityLevel, "info" | "warn" | "error" | null> = { debug: null, info: "info", warn: "warn", error: "error" };

let running = false;
const raised = new Set<string>();

export interface ReportingOptions {
  readonly enabled: boolean;
  readonly channel: Channel;
  readonly version: string;
}

export const startReporting = (options: ReportingOptions): void => {
  if (!options.enabled || running) return;
  running = true;
  Sentry.init({
    dsn: sentryDsn("gateway", options.channel),
    environment: options.channel,
    release: `vitals-gateway@${options.version}`,
    serverName: "vitals-gateway",
    dataCollection: { userInfo: false, cookies: false, httpHeaders: false, httpBodies: [], urlQueryParams: false },
    beforeSend: (event) => {
      delete event.request;
      return scrubEvent(event);
    },
    beforeBreadcrumb: (crumb) => scrubBreadcrumb(crumb),
    beforeSendLog: (log) => ({ ...log, message: scrubText(String(log.message)), ...(log.attributes === undefined ? {} : { attributes: scrubRecord(log.attributes) }) }),
  });
};

const tagOf = (error: unknown): string => {
  if (typeof error === "object" && error !== null && "_tag" in error && typeof error._tag === "string") return error._tag;
  return error instanceof Error ? error.name : typeof error;
};

const messageOf = (error: unknown): string => scrubText(error instanceof Error ? error.message : String(error));

const reportCause = (cause: Cause.Cause<unknown>, tags: Record<string, string>): void => {
  if (!running || Cause.hasInterruptsOnly(cause)) return;
  const error = Cause.squash(cause);
  const defect = Cause.hasDies(cause);
  Sentry.withScope((scope) => {
    scope.setLevel(defect ? "fatal" : "error");
    scope.setTags({ ...tags, "effect.failure": defect ? "defect" : "failure", "effect.tag": tagOf(error) });
    scope.setExtra("cause", scrubText(Cause.pretty(cause)).slice(0, 4_000));
    Sentry.captureException(error instanceof Error ? error : new Error(messageOf(error)));
  });
};

export const reportRpcFailure = (rpc: string, cause: Cause.Cause<unknown>): void => {
  if (!running || Cause.hasInterruptsOnly(cause)) return;
  if (Cause.hasDies(cause)) return reportCause(cause, { rpc });
  const error = Cause.squash(cause);
  Sentry.logger.warn(`rpc ${rpc} failed: ${tagOf(error)}`, { rpc, "effect.tag": tagOf(error), message: messageOf(error) });
};

export const reportActivity = (event: ActivityEvent): void => {
  if (!running || event.source !== "gateway") return;
  const level = ACTIVITY_LEVEL[event.level];
  if (level === null) return;
  const attributes = { kind: event.kind, ...(event.rpc === null || event.rpc === undefined ? {} : { rpc: event.rpc }), ...(level === "info" ? {} : scrubRecord(event.data ?? {})) };
  Sentry.logger[level](event.kind, attributes);
  if (level !== "error" || raised.has(event.kind)) return;
  raised.add(event.kind);
  Sentry.withScope((scope) => {
    scope.setFingerprint(["activity", event.kind]);
    scope.setTag("kind", event.kind);
    scope.setExtras(scrubRecord(event.data ?? {}));
    Sentry.captureMessage(event.kind, "error");
  });
};

const sentryLogger = Logger.make(({ message, logLevel, cause }) => {
  const level = SENTRY_LEVEL[logLevel];
  if (!running || level === undefined) return;
  const text = scrubText((Array.isArray(message) ? message : [message]).map((part) => (typeof part === "string" ? part : JSON.stringify(part))).join(" "));
  Sentry.logger[level](text);
  if ((level === "error" || level === "fatal") && (Cause.hasFails(cause) || Cause.hasDies(cause))) reportCause(cause, { source: "effect.log" });
});

export const reportingLoggerLayer = Logger.layer([sentryLogger], { mergeWithExisting: true });

const flushReports: Effect.Effect<void> = Effect.promise(() => (running ? Sentry.flush(2_000) : Promise.resolve(true))).pipe(Effect.asVoid);

export const reportExit = <A, E, R>(self: Effect.Effect<A, E, R>): Effect.Effect<A, E, R> =>
  self.pipe(
    Effect.tapCause((cause) => Effect.sync(() => reportCause(cause, { source: "main" }))),
    Effect.ensuring(flushReports),
  );
