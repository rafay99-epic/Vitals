import type { Clip, ClipKind, DeviceId } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";

/** One word per kind, for sheet titles and fallbacks. */
export const KIND_NAME: Readonly<Record<ClipKind, string>> = { text: "Text", link: "Link", image: "Image", file: "File", folder: "Folder" };

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;

/** Terminal apps whose copies read as commands, shown in mono. */
const TERMINALS: ReadonlySet<string> = new Set(["Terminal", "iTerm2", "Ghostty", "Warp", "kitty", "Alacritty", "WezTerm", "Hyper", "Tabby"]);

/** What a row shows: links without the scheme, text on one line, files by name. */
export const clipTitle = (clip: Clip): string => {
  if (clip.kind === "text" || clip.kind === "link") return (clip.text ?? "").replace(/^https?:\/\//, "").replace(/\s+/g, " ").trim() || KIND_NAME[clip.kind];
  return clip.name ?? KIND_NAME[clip.kind];
};

/** A one-line copy from a terminal is a command. */
export const isCommand = (clip: Clip): boolean => clip.kind === "text" && clip.source !== null && TERMINALS.has(clip.source) && !(clip.text ?? "").includes("\n");

/** Size as the Mac reports it. Folders are zipped on the first download, so their size shows up after that. */
export const clipSize = (clip: Clip): string | null => {
  if (clip.kind === "folder") {
    const files = clip.files === null ? null : `${String(clip.files)} ${clip.files === 1 ? "file" : "files"}`;
    const zip = clip.bytes > 0 ? `${formatBytes(clip.bytes)} as zip` : null;
    return [files, zip].filter((part) => part !== null).join(" · ") || null;
  }
  return clip.kind === "image" || clip.kind === "file" ? (clip.bytes > 0 ? formatBytes(clip.bytes) : null) : null;
};

/** "now", "5 min", "2 h", "Yesterday", then a date. */
export const clipAge = (at: number, now: number): string => {
  const gap = Math.max(0, now - at);
  if (gap < MINUTE) return "now";
  if (gap < HOUR) return `${String(Math.floor(gap / MINUTE))} min`;
  if (isSameDay(at, now)) return `${String(Math.floor(gap / HOUR))} h`;
  if (isSameDay(at, now - 24 * HOUR)) return "Yesterday";
  return new Date(at).toLocaleDateString([], { month: "short", day: "numeric" });
};

export const isSameDay = (left: number, right: number): boolean => new Date(left).toDateString() === new Date(right).toDateString();

/** Who copied it: the Mac app, this phone, or another phone by name. */
/** Who made the clip. `here` names this device: "this phone" in the app, "this browser" on the web. */
export const clipWho = (clip: Clip, me: DeviceId, here = "this phone"): string | null =>
  clip.deviceId === null ? clip.source : clip.deviceId === me ? `From ${here}` : clip.source;

/** "Safari · 1.8 MB · 5 min" */
export const clipMeta = (clip: Clip, me: DeviceId, now: number, here?: string): string =>
  [clipWho(clip, me, here), clipSize(clip), clipAge(clip.at, now)].filter((part) => part !== null && part !== "").join(" · ");

/** A name to save the clip's bytes under. Folders arrive as a zip. */
export const fileNameOf = (clip: Clip): string => {
  const name = clip.name ?? `${KIND_NAME[clip.kind]} ${new Date(clip.at).toISOString().slice(0, 10)}`;
  return clip.kind === "folder" && !name.endsWith(".zip") ? `${name}.zip` : name;
};

/** A typed or pasted string is a link when it is one http(s) URL and nothing else. */
export const isLink = (text: string): boolean => /^https?:\/\/\S+$/.test(text.trim());

const UNITS = ["B", "KB", "MB", "GB"] as const;

/** "3.1 of 7.9 MB": both numbers in the total's unit. */
export const formatAmount = (done: number, total: number): string => {
  const exponent = total <= 0 ? 0 : Math.min(UNITS.length - 1, Math.floor(Math.log(total) / Math.log(1024)));
  const scale = 1024 ** exponent;
  const digits = exponent === 0 ? 0 : 1;
  return `${(done / scale).toFixed(digits)} of ${(total / scale).toFixed(digits)} ${UNITS[exponent] ?? "B"}`;
};
