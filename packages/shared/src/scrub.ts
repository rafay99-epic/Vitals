/**
 * Scrubbing shared by every reporter that sends text to Sentry: the phone app (`apps/mobile/src/lib/scrub.ts`)
 * and the gateway (`apps/gateway/src/reporting`). The Mac app's `Scrub.swift` follows the same rules.
 */
const FILE_TYPES = "png|jpe?g|heic|heif|gif|webp|svg|mp4|mov|m4v|mkv|mp3|m4a|wav|aac|pdf|docx?|xlsx?|pptx?|key|pages|numbers|txt|md|rtf|csv|json|xml|zip|tar|gz|dmg|pkg|apk|ipa|app|plist|sqlite3?|log";

/**
 * What never leaves a device for Sentry: links (Mac and tailnet addresses), email addresses, IP
 * addresses, .local host names, folder paths and file names. Mirrored by the Mac's `Scrub.swift`.
 * Order matters: whole links go before the paths inside them.
 */
const RULES: ReadonlyArray<readonly [RegExp, string]> = [
  [/\b[a-z][a-z0-9+.-]*:\/\/[^\s"'<>)]+/gi, "<url>"],
  [/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, "<email>"],
  [/\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b/g, "<ip>"],
  [/\b[\w-]+(?:\.[\w-]+)*\.ts\.net\b/gi, "<host>"],
  [/\b[\w-]+\.local\b/gi, "<host>"],
  // IPv6: four or more groups, or a "fe80::" form, so a time (11:10:46) stays.
  [/(?:\b[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b(?:%\w+)?|\b[0-9a-f]{1,4}::(?:[0-9a-f]{1,4}:?){0,6}\b(?:%\w+)?/gi, "<ip>"],
  // iOS names a file in “curly quotes”.
  [/“[^”\n]{1,200}”/g, "“<name>”"],
  [/(?:~|\b[A-Za-z]:)?(?:\/[^\s/"'<>:]+){2,}\/?/g, "<path>"],
  // A name.ext not followed by more ".word", so `client.app.fg` (a log kind) stays.
  [new RegExp(`[^\\s/\\\\"'<>]+\\.(?:${FILE_TYPES})\\b(?!\\.\\w)`, "gi"), "<file>"],
];

export const scrubText = (text: string): string => RULES.reduce((out, [pattern, label]) => out.replace(pattern, label), text);

/** Strings get scrubbed at any depth (connection failures nest their reasons); numbers and flags pass. */
const scrubValue = (value: unknown): unknown => {
  if (typeof value === "string") return scrubText(value);
  if (Array.isArray(value)) return value.map(scrubValue);
  if (typeof value === "object" && value !== null) return scrubRecord(Object.fromEntries(Object.entries(value)));
  return value;
};

export const scrubRecord = (record: Readonly<Record<string, unknown>>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(record).map(([key, value]) => [key, scrubValue(value)]));

/** The parts of a Sentry breadcrumb that can carry text. Both SDKs' `Breadcrumb` types fit it. */
interface CrumbShape {
  message?: string;
  data?: Record<string, unknown>;
}

/** The parts of a Sentry event that can name someone. Both SDKs' `ErrorEvent` types fit it. */
interface EventShape {
  message?: string;
  exception?: { values?: Array<{ value?: string }> };
  breadcrumbs?: Array<CrumbShape>;
  extra?: Record<string, unknown>;
  user?: unknown;
  server_name?: string;
  contexts?: { device?: { name?: string } };
}

/** Scrubs a breadcrumb in place (Sentry hands its own copy to `beforeBreadcrumb`). */
export const scrubBreadcrumb = <C extends CrumbShape>(crumb: C): C => {
  if (crumb.message !== undefined) crumb.message = scrubText(crumb.message);
  if (crumb.data !== undefined) crumb.data = scrubRecord(crumb.data);
  return crumb;
};

/** Scrubs an event in place: messages and breadcrumbs, and nothing that names the device or its owner. */
export const scrubEvent = <E extends EventShape>(event: E): E => {
  delete event.user;
  delete event.server_name;
  delete event.contexts?.device?.name;
  if (event.message !== undefined) event.message = scrubText(event.message);
  for (const value of event.exception?.values ?? []) if (value.value !== undefined) value.value = scrubText(value.value);
  for (const crumb of event.breadcrumbs ?? []) scrubBreadcrumb(crumb);
  if (event.extra !== undefined) event.extra = scrubRecord(event.extra);
  return event;
};
