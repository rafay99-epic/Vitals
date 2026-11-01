import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { type BrowseCache, decodeBrowseCache, type KindPage, type SeenFolder, type SeenPages } from "@vitals/app/state/files.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import type { DeviceId, FsEntry } from "@vitals/contracts";
import { File, Paths } from "expo-file-system";
import { useEffect } from "react";
import { AppState } from "react-native";

/**
 * Pages and thumbnails seen while browsing the Mac and other phones, kept on disk so a screen opens
 * on them at once, even after a restart, while the device is asked again. Only what was shown is
 * kept, each with when it was seen, so the screens can say how old it is.
 */
/** Files per recent page: what Files fetches ahead and a Recent screen shows first. */
export const RECENT_PAGE = 60;

/** A page seen this recently opens as current, with no "From … · updating" line. */
export const FRESH_MS = 20_000;
const KEEP_PAGES = 40;
const KEEP_FOLDERS = 60;
const KEEP_THUMBS = 300;
const SAVE_DELAY_MS = 10_000;

export const recentSeen = new Map<string, SeenPages>();
export const folderSeen = new Map<string, SeenFolder>();

export const recentKey = (kind: string, device?: DeviceId): string => `${device ?? "mac"}:${kind}`;
export const folderKey = (path: string, device?: DeviceId): string => `${device ?? "mac"}:${path}`;

const file = () => new File(Paths.cache, "browse-v1.json");

/** Newest last, at most `keep`: a Map remembers insertion order, so re-setting a key moves it to the end. */
const remember = <V>(map: Map<string, V>, key: string, value: V, keep: number): void => {
  map.delete(key);
  map.set(key, value);
  for (const oldest of map.keys()) {
    if (map.size <= keep) break;
    map.delete(oldest);
  }
};

let dirty = false;
let timer: ReturnType<typeof setTimeout> | null = null;
let thumbsOf: (() => ReadonlyMap<string, string | null>) | null = null;
/** The pairing the maps above belong to: this phone's device id in it. */
let owner: string | null = null;

const save = (): void => {
  if (timer !== null) clearTimeout(timer);
  timer = null;
  if (!dirty || thumbsOf === null || owner === null) return;
  dirty = false;
  const thumbs = [...thumbsOf().entries()].filter((entry): entry is [string, string] => entry[1] !== null).slice(-KEEP_THUMBS);
  try {
    const cache: BrowseCache = { owner, recent: [...recentSeen], folders: [...folderSeen], thumbs };
    file().write(JSON.stringify(cache));
  } catch {
    dirty = true;
  }
};

const changed = (): void => {
  dirty = true;
  timer ??= setTimeout(save, SAVE_DELAY_MS);
};

export const seeRecent = (key: string, pages: ReadonlyArray<KindPage>): void => {
  remember(recentSeen, key, { at: Date.now(), pages }, KEEP_PAGES);
  changed();
};

export const seeFolder = (key: string, entries: ReadonlyArray<FsEntry>, total: number): void => {
  remember(folderSeen, key, { at: Date.now(), entries, total }, KEEP_FOLDERS);
  changed();
};

/**
 * Loads what this pairing kept into the screens' maps and `remote`'s thumbnails (another pairing's is
 * dropped, so a different Mac never shows the last one's pages), then keeps the file current:
 * soon after a change, and at once when the app leaves the screen. Returns the stop.
 */
const keepBrowseCache = (remote: Remote): (() => void) => {
  const me = remote.credentials.deviceId;
  if (owner !== me) {
    recentSeen.clear();
    folderSeen.clear();
  }
  owner = me;
  thumbsOf = () => remote.files.thumbs.get();
  try {
    const target = file();
    const saved = target.exists ? decodeBrowseCache(target.textSync()) : null;
    if (saved?._tag === "Some" && saved.value.owner === me) {
      for (const [key, value] of saved.value.recent) if (!recentSeen.has(key)) recentSeen.set(key, value);
      for (const [key, value] of saved.value.folders) if (!folderSeen.has(key)) folderSeen.set(key, value);
      remote.files.thumbs.update((current) => new Map([...saved.value.thumbs, ...current]));
    }
  } catch {
    // A missing or unreadable file only means starting cold.
  }
  const stopThumbs = remote.files.thumbs.subscribe(changed);
  const appState = AppState.addEventListener("change", (next) => next !== "active" && save());
  return () => {
    stopThumbs();
    appState.remove();
    save();
    thumbsOf = null;
  };
};

/** Keeps the browse cache for the paired Mac while the app shell is up. */
export const useBrowseCache = (): void => {
  const remote = useRemote();
  useEffect(() => keepBrowseCache(remote), [remote]);
};
