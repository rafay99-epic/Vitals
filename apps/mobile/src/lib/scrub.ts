import type { Breadcrumb, ErrorEvent, ReactNativeOptions } from "@sentry/react-native";

type Log = Parameters<NonNullable<ReactNativeOptions["beforeSendLog"]>>[0];

const FILE_TYPES = "png|jpe?g|heic|heif|gif|webp|svg|mp4|mov|m4v|mkv|mp3|m4a|wav|aac|pdf|docx?|xlsx?|pptx?|key|pages|numbers|txt|md|rtf|csv|json|xml|zip|tar|gz|dmg|pkg|apk|ipa|app";

/**
 * What never leaves the phone for Sentry: links (Mac and tailnet addresses), email addresses, IP
 * addresses, folder paths and file names. Order matters: whole links go before the paths inside them.
 */
const RULES: ReadonlyArray<readonly [RegExp, string]> = [
  [/\b[a-z][a-z0-9+.-]*:\/\/[^\s"'<>)]+/gi, "<url>"],
  [/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, "<email>"],
  [/\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b/g, "<ip>"],
  [/\b[\w-]+(?:\.[\w-]+)*\.ts\.net\b/gi, "<host>"],
  [/(?:~|\b[A-Za-z]:)?(?:\/[^\s/"'<>:]+){2,}\/?/g, "<path>"],
  [new RegExp(`[^\\s/\\\\"'<>]+\\.(?:${FILE_TYPES})\\b`, "gi"), "<file>"],
];

export const scrubText = (text: string): string => RULES.reduce((out, [pattern, label]) => out.replace(pattern, label), text);

/** Strings get scrubbed; numbers and flags pass. */
export const scrubRecord = (record: Readonly<Record<string, unknown>>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(record).map(([key, value]) => [key, typeof value === "string" ? scrubText(value) : value]));

export const scrubBreadcrumb = (crumb: Breadcrumb): Breadcrumb => ({
  ...crumb,
  ...(crumb.message === undefined ? {} : { message: scrubText(crumb.message) }),
  ...(crumb.data === undefined ? {} : { data: scrubRecord(crumb.data) }),
});

const withoutName = <T extends { readonly name?: string }>({ name: _name, ...rest }: T): Omit<T, "name"> => rest;

/** Error messages and breadcrumbs scrubbed, and nothing that names the phone or its owner. */
export const scrubEvent = (event: ErrorEvent): ErrorEvent => {
  const { user: _user, server_name: _server, ...rest } = event;
  const device = event.contexts?.device;
  return {
    ...rest,
    ...(event.message === undefined ? {} : { message: scrubText(event.message) }),
    ...(event.exception?.values === undefined
      ? {}
      : { exception: { ...event.exception, values: event.exception.values.map((value) => (value.value === undefined ? value : { ...value, value: scrubText(value.value) })) } }),
    ...(event.breadcrumbs === undefined ? {} : { breadcrumbs: event.breadcrumbs.map(scrubBreadcrumb) }),
    ...(event.extra === undefined ? {} : { extra: scrubRecord(event.extra) }),
    ...(device === undefined ? {} : { contexts: { ...event.contexts, device: withoutName(device) } }),
  };
};

export const scrubLog = (log: Log): Log => ({
  ...log,
  message: scrubText(String(log.message)),
  ...(log.attributes === undefined ? {} : { attributes: scrubRecord(log.attributes) }),
});
