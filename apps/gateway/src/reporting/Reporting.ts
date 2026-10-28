import * as Sentry from "@sentry/bun";
import type { ActivityLevel } from "@vitals/contracts";
import { scrubBreadcrumb, scrubEvent, scrubRecord, scrubText } from "@vitals/shared";
import * as Cause from "effect/Cause";
import * as Effect from "effect/Effect";
import * as Logger from "effect/Logger";
import type * as LogLevel from "effect/LogLevel";

import type { ActivityEvent } from "../activity/ActivityLog.ts";
import type { Channel } from "../config.ts";

/** Public by design: a DSN only lets an app send events to the Vitals Gateway project. */
const DSN = "https://6d258fdca2210b1a67d0f102a7c5a0cc@o4512219615920128.ingest.us.sentry.io/4512333741359104";

/** Effect's log levels in Sentry's words. Trace and Debug stay local: they would drown everything else. */
const SENTRY_LEVEL: Partial<Record<LogLevel.LogLevel, "info" | "warn" | "error" | "fatal">> = {
  Info: "info",
  Warn: "warn",
  Error: "error",
  Fatal: "fatal",
};

const ACTIVITY_LEVEL: Record<ActivityLevel, "info" | "warn" | "error" | null> = { debug: null, info: "info", warn: "warn", error: "error" };

let running = false;
/** Activity kinds already raised as issues this run, so a failure in a loop is one event, not thousands. */
const raised = new Set<string>();

export interface ReportingOptions {
  /** The Mac's Settings → Developer → Crash reports switch, passed as `VITALS_ERROR_REPORTS=1`. */
  readonly enabled: boolean;
  readonly channel: Channel;
  readonly version: string;
}

/**
 * Sentry for the gateway (project `vitals-gateway`): uncaught exceptions and rejections, Effect
 * failures and logs, failed RPCs, and the gateway's own activity warnings. Everything passes the
 * shared scrubber first. Off unless the Mac app turned it on, so tests and fake-mac send nothing.
 */
export const startReporting = (options: ReportingOptions): void => {
  if (!options.enabled || running) return;
  running = true;
  Sentry.init({
    dsn: DSN,
    environment: options.channel,
    release: `vitals-gateway@${options.version}`,
    // Otherwise the Mac's host name.
    serverName: "vitals-gateway",
    // Collect nothing from requests: headers carry the Tailscale owner login and the session cookie,
    // bodies carry pairing codes and clipboard text.
    dataCollection: { userInfo: false, cookies: false, httpHeaders: false, httpBodies: [], urlQueryParams: false },
    beforeSend: (event) => {
      delete event.request;
      return scrubEvent(event);
    },
    beforeBreadcrumb: (crumb) => scrubBreadcrumb(crumb),
    beforeSendLog: (log) => ({ ...log, message: scrubText(String(log.message)), ...(log.attributes === undefined ? {} : { attributes: scrubRecord(log.attributes) }) }),
  });
};

/** What a failure is, for grouping and search: a tagged error's `_tag`, an Error's name, or the value's type. */
const tagOf = (error: unknown): string => {
  if (typeof error === "object" && error !== null && "_tag" in error && typeof error._tag === "string") return error._tag;
  return error instanceof Error ? error.name : typeof error;
};

const messageOf = (error: unknown): string => scrubText(error instanceof Error ? error.message : String(error));

/**
 * Raises a Cause as a Sentry issue: a defect (a bug, a thrown exception) as fatal, a typed failure
 * as an error, tagged with the failure's `_tag` and the full Effect cause. Interruptions are not failures.
 */
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

/**
 * A finished RPC that failed. Defects are bugs and become issues; typed failures (`AuthError`,
 * `CommandRejected`, `Unavailable`) are answers the phone was given, so they are log lines.
 */
export const reportRpcFailure = (rpc: string, cause: Cause.Cause<unknown>): void => {
  if (!running || Cause.hasInterruptsOnly(cause)) return;
  if (Cause.hasDies(cause)) return reportCause(cause, { rpc });
  const error = Cause.squash(cause);
  Sentry.logger.warn(`rpc ${rpc} failed: ${tagOf(error)}`, { rpc, "effect.tag": tagOf(error), message: messageOf(error) });
};

/**
 * The gateway's own activity lines (not the phone's, which reports itself, nor the Mac's). Info is a
 * log line with no data, since data can name a device; warnings and errors carry scrubbed data, and
 * each error kind is also raised as an issue once per run.
 */
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

/** Every Effect log at Info or above becomes a Sentry log line; one that carries a failure also raises it. */
const sentryLogger = Logger.make(({ message, logLevel, cause }) => {
  const level = SENTRY_LEVEL[logLevel];
  if (!running || level === undefined) return;
  const text = scrubText((Array.isArray(message) ? message : [message]).map((part) => (typeof part === "string" ? part : JSON.stringify(part))).join(" "));
  Sentry.logger[level](text);
  if ((level === "error" || level === "fatal") && (Cause.hasFails(cause) || Cause.hasDies(cause))) reportCause(cause, { source: "effect.log" });
});

/** Adds the Sentry logger next to the default one, for every fiber in the app. */
export const reportingLoggerLayer = Logger.layer([sentryLogger], { mergeWithExisting: true });

/** Sends what's queued before the process exits (two seconds at most). */
const flushReports: Effect.Effect<void> = Effect.promise(() => (running ? Sentry.flush(2_000) : Promise.resolve(true))).pipe(Effect.asVoid);

/** For `main.ts`: report a failure that ends the gateway, then flush. */
export const reportExit = <A, E, R>(self: Effect.Effect<A, E, R>): Effect.Effect<A, E, R> =>
  self.pipe(
    Effect.tapCause((cause) => Effect.sync(() => reportCause(cause, { source: "main" }))),
    Effect.ensuring(flushReports),
  );
