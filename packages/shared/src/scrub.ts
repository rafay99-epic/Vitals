const FILE_TYPES = "png|jpe?g|heic|heif|gif|webp|svg|mp4|mov|m4v|mkv|mp3|m4a|wav|aac|pdf|docx?|xlsx?|pptx?|key|pages|numbers|txt|md|rtf|csv|json|xml|zip|tar|gz|dmg|pkg|apk|ipa|app|plist|sqlite3?|log";

const RULES: ReadonlyArray<readonly [RegExp, string]> = [
  [/\b[a-z][a-z0-9+.-]*:\/\/[^\s"'<>)]+/gi, "<url>"],
  [/[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,}\b/g, "<email>"],
  [/\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b/g, "<ip>"],
  [/\b[\w-]+(?:\.[\w-]+)*\.ts\.net\b/gi, "<host>"],
  [/\b[\w-]+\.local\b/gi, "<host>"],
  [/(?:\b[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b(?:%\w+)?|\b[0-9a-f]{1,4}::(?:[0-9a-f]{1,4}:?){0,6}\b(?:%\w+)?/gi, "<ip>"],
  [/“[^”\n]{1,200}”/g, "“<name>”"],
  [/(?:~|\b[A-Za-z]:)?(?:\/[^\s/"'<>:]+){2,}\/?/g, "<path>"],
  [new RegExp(`[^\\s/\\\\"'<>]+\\.(?:${FILE_TYPES})\\b(?!\\.\\w)`, "gi"), "<file>"],
];

export const scrubText = (text: string): string => RULES.reduce((out, [pattern, label]) => out.replace(pattern, label), text);

const scrubValue = (value: unknown): unknown => {
  if (typeof value === "string") return scrubText(value);
  if (Array.isArray(value)) return value.map(scrubValue);
  if (typeof value === "object" && value !== null) return scrubRecord(Object.fromEntries(Object.entries(value)));
  return value;
};

export const scrubAttributes = (attributes: Readonly<Record<string, unknown>>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(attributes).map(([key, value]) => [key, key.startsWith("sentry.") ? value : scrubValue(value)]));

export const scrubRecord = (record: Readonly<Record<string, unknown>>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(record).map(([key, value]) => [key, scrubValue(value)]));

interface CrumbShape {
  message?: string;
  data?: Record<string, unknown>;
}

interface EventShape {
  message?: string;
  exception?: { values?: Array<{ value?: string }> };
  breadcrumbs?: Array<CrumbShape>;
  extra?: Record<string, unknown>;
  user?: unknown;
  server_name?: string;
  contexts?: { device?: { name?: string } };
}

export const scrubBreadcrumb = <C extends CrumbShape>(crumb: C): C => {
  if (crumb.message !== undefined) crumb.message = scrubText(crumb.message);
  if (crumb.data !== undefined) crumb.data = scrubRecord(crumb.data);
  return crumb;
};

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
