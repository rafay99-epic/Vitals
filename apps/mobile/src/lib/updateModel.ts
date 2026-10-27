/**
 * The rules behind updates, free of native modules so they can be tested: what the Updates page
 * says, which sheet opens, and whether a quick update downloads on this network.
 */

/** Quick updates (over the air). `id` is the update's id, so each one is offered once. */
export type UpdateState =
  | { readonly _tag: "Off" }
  | { readonly _tag: "Idle" }
  | { readonly _tag: "Checking" }
  | { readonly _tag: "Found"; readonly id: string; readonly notes: string }
  | { readonly _tag: "Downloading"; readonly progress: number }
  | { readonly _tag: "Ready"; readonly id: string; readonly notes: string }
  | { readonly _tag: "Current"; readonly at: number }
  | { readonly _tag: "Failed"; readonly at: number; readonly reason: string; readonly step: "check" | "download" };

/** App updates from Google Play. `version` is the versionCode, which is the 0.<n> in the version name. */
export type PlayState =
  | { readonly _tag: "Off"; readonly reason: string }
  | { readonly _tag: "Unchecked" }
  | { readonly _tag: "Current" }
  | { readonly _tag: "Available"; readonly version: number }
  | { readonly _tag: "Downloading"; readonly version: number; readonly progress: number }
  | { readonly _tag: "Stopped"; readonly version: number; readonly reason: "blocked" | "download" }
  | { readonly _tag: "Downloaded"; readonly version: number };

/** When a found quick update downloads by itself. */
export type QuickUpdates = "wifi" | "any" | "ask";

export const QUICK_UPDATES: ReadonlyArray<{ readonly value: QuickUpdates; readonly label: string }> = [
  { value: "wifi", label: "Wi-Fi" },
  { value: "any", label: "Any network" },
  { value: "ask", label: "Ask first" },
];

export const downloadsNow = (choice: QuickUpdates, network: "wifi" | "cellular" | "other"): boolean => choice === "any" || (choice === "wifi" && network !== "cellular");

const COMMIT_PREFIX = /^\w+(\([^)]*\))?!?:\s*/;

/** Release notes as a sentence. Commit subjects lose their "fix(mobile): " prefix. */
export const tidyNotes = (raw: string): string => {
  const text = raw.trim().replace(COMMIT_PREFIX, "");
  if (text === "") return "";
  const sentence = text.charAt(0).toUpperCase() + text.slice(1);
  return /[.!?]$/.test(sentence) ? sentence : `${sentence}.`;
};

/** The notes an update was published with: app.config.ts puts them in `extra.updateNotes`. */
export const notesOf = (manifest: unknown): string => {
  let at: unknown = manifest;
  for (const key of ["extra", "expoClient", "extra", "updateNotes"]) {
    if (typeof at !== "object" || at === null || !(key in at)) return "";
    at = (at as Record<string, unknown>)[key];
  }
  return typeof at === "string" ? tidyNotes(at) : "";
};

export const playVersion = (version: number): string => `0.${String(version)}`;

/** The one thing the Updates page says, most urgent first. */
export type UpdateView =
  | { readonly kind: "off" }
  | { readonly kind: "current"; readonly checked: boolean }
  | { readonly kind: "checking" }
  | { readonly kind: "found"; readonly notes: string }
  | { readonly kind: "downloading"; readonly progress: number }
  | { readonly kind: "ready"; readonly notes: string }
  | { readonly kind: "failed"; readonly step: "check" | "download"; readonly reason: string }
  | { readonly kind: "play-found"; readonly version: number }
  | { readonly kind: "play-downloading"; readonly progress: number }
  | { readonly kind: "play-stopped"; readonly reason: "blocked" | "download" }
  | { readonly kind: "play-ready"; readonly version: number }
  | { readonly kind: "rolled-back" };

export const updateView = (quick: UpdateState, play: PlayState, rolledBack: boolean): UpdateView => {
  if (play._tag === "Downloaded") return { kind: "play-ready", version: play.version };
  if (quick._tag === "Ready") return { kind: "ready", notes: quick.notes };
  if (quick._tag === "Downloading") return { kind: "downloading", progress: quick.progress };
  if (play._tag === "Downloading") return { kind: "play-downloading", progress: play.progress };
  if (play._tag === "Stopped") return { kind: "play-stopped", reason: play.reason };
  if (quick._tag === "Checking") return { kind: "checking" };
  if (quick._tag === "Failed") return { kind: "failed", step: quick.step, reason: quick.reason };
  if (play._tag === "Available") return { kind: "play-found", version: play.version };
  if (quick._tag === "Found") return { kind: "found", notes: quick.notes };
  if (rolledBack) return { kind: "rolled-back" };
  if (quick._tag === "Off" && play._tag === "Off") return { kind: "off" };
  return { kind: "current", checked: quick._tag === "Current" };
};

/** The Settings row's word for a view, and whether it waits on the user (yellow, plus a dot on the tab). */
export const SETTINGS_WORD: Readonly<Record<UpdateView["kind"], { readonly word: string; readonly waiting: boolean }>> = {
  off: { word: "Off in this build", waiting: false },
  current: { word: "Up to date", waiting: false },
  checking: { word: "Checking", waiting: false },
  found: { word: "Ready to download", waiting: true },
  downloading: { word: "Downloading", waiting: false },
  ready: { word: "Restart", waiting: true },
  failed: { word: "Couldn't check", waiting: false },
  "play-found": { word: "On Google Play", waiting: true },
  "play-downloading": { word: "Downloading", waiting: false },
  "play-stopped": { word: "Paused", waiting: true },
  "play-ready": { word: "Restart", waiting: true },
  "rolled-back": { word: "Previous version", waiting: false },
};

/** A sheet that tells the user about an update. `key` is how it's shown only once. */
export type UpdateSheet =
  | { readonly kind: "play-ready"; readonly key: string; readonly version: number }
  | { readonly kind: "ready"; readonly key: string; readonly notes: string }
  | { readonly kind: "found"; readonly key: string; readonly id: string; readonly notes: string }
  | { readonly kind: "play-found"; readonly key: string; readonly version: number };

/**
 * Which sheet to open, if any. A finished Play download asks right away, since the user started it.
 * Everything else waits for the app to come to the front (`fresh`), so a sheet never lands mid-task.
 * `skippedPlay` is the Play version the user said Later to; it stays quiet until a newer one.
 */
export const sheetFor = (input: {
  readonly quick: UpdateState;
  readonly play: PlayState;
  readonly fresh: boolean;
  readonly shown: ReadonlySet<string>;
  readonly skippedPlay: number | null;
}): UpdateSheet | null => {
  const { quick, play, fresh, shown } = input;
  const once = (sheet: UpdateSheet): UpdateSheet | null => (shown.has(sheet.key) ? null : sheet);
  const candidates: ReadonlyArray<UpdateSheet | null> = [
    play._tag === "Downloaded" ? { kind: "play-ready", key: `play-ready:${String(play.version)}`, version: play.version } : null,
    fresh && quick._tag === "Ready" ? { kind: "ready", key: `ready:${quick.id}`, notes: quick.notes } : null,
    fresh && quick._tag === "Found" ? { kind: "found", key: `found:${quick.id}`, id: quick.id, notes: quick.notes } : null,
    fresh && play._tag === "Available" && play.version !== input.skippedPlay ? { kind: "play-found", key: `play-found:${String(play.version)}`, version: play.version } : null,
  ];
  return candidates.map((sheet) => (sheet === null ? null : once(sheet))).find((sheet) => sheet !== null) ?? null;
};
