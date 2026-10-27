import { Store } from "@vitals/client-runtime";
import { deviceInfo } from "@vitals/app/lib/device.ts";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import type { OutgoingFile } from "@vitals/app/state/drops.ts";
import { FS_LIMITS, type FsEntry, type FsListResult, type FsRecentKind, type FsRecentResult, type FsRoot, type FsServeRequest, type FsServeResult, type FsSort, type FsThumb } from "@vitals/contracts";
import { Directory, File, Paths } from "expo-file-system";
import * as SecureStore from "expo-secure-store";
import { useEffect, useState } from "react";
import { AppState, Linking, Platform } from "react-native";

import { androidShare, iosShare, type NativeEntry, type NativePage, type PhotosAccess, type SharedFolder } from "../../modules/vitals-share/index.ts";

const KEY = "vitals.remote.shareFiles";
const PHOTOS_KEY = "vitals.remote.sharePhotos";
const STORAGE = "/storage/emulated/0";
const PHOTOS = "/photos";
const CACHE_MS = 5_000;
const THUMB_BYTES = 400_000;
const SEND_LIMIT = 2_000;
const WALK_LIMIT = 5_000;
const WALK_DEPTH = 6;
const IMAGE = /\.(jpe?g|png|gif|webp|heic|heif)$/i;
const MEDIA = /\.(jpe?g|png|gif|webp|heic|heif|bmp|dng|mp4|m4v|mov|mkv|webm|3gp)$/i;

export const shareFiles = new Store<boolean>(false);
let changed = false;

void SecureStore.getItemAsync(KEY, KEYCHAIN_OPTIONS)
  .then((value) => changed || shareFiles.set(value === "1"))
  .catch(() => undefined);

export const setShareFiles = (on: boolean): void => {
  changed = true;
  shareFiles.set(on);
  void SecureStore.setItemAsync(KEY, on ? "1" : "0", KEYCHAIN_OPTIONS).catch(() => undefined);
};

/** iPhone only: Photos and screenshots are shared too. Turned on only once iOS allows reading them. */
export const sharePhotos = new Store<boolean>(false);
let photosChanged = false;

/** iPhone only: folders picked in Files, opened for reading. */
export const sharedFolders = new Store<ReadonlyArray<SharedFolder>>([]);

if (iosShare !== null) {
  void SecureStore.getItemAsync(PHOTOS_KEY, KEYCHAIN_OPTIONS)
    .then((value) => photosChanged || sharePhotos.set(value === "1"))
    .catch(() => undefined);
  void iosShare
    .folders()
    .then((folders) => sharedFolders.set(folders))
    .catch(() => undefined);
}

const savePhotos = (on: boolean): void => {
  photosChanged = true;
  sharePhotos.set(on);
  void SecureStore.setItemAsync(PHOTOS_KEY, on ? "1" : "0", KEYCHAIN_OPTIONS).catch(() => undefined);
};

/** Turns iPhone Photos sharing on or off. Asks iOS once; says no when iOS says no. */
export const setSharePhotos = async (on: boolean): Promise<PhotosAccess | null> => {
  if (iosShare === null) return null;
  if (!on) {
    savePhotos(false);
    return null;
  }
  const current = await iosShare.photosAccess();
  const access = current === "ask" ? await iosShare.askPhotos() : current;
  savePhotos(access === "full" || access === "limited");
  return access;
};

/** Picks a folder in Files for `role`. A new Downloads or Documents folder replaces the old one. */
export const pickSharedFolder = async (role: SharedFolder["role"]): Promise<SharedFolder | null> => {
  if (iosShare === null) return null;
  const folder = await iosShare.pickFolder(role);
  if (folder !== null) sharedFolders.set(await iosShare.folders());
  return folder;
};

export const removeSharedFolder = async (id: string): Promise<void> => {
  if (iosShare === null) return;
  await iosShare.removeFolder(id);
  sharedFolders.set(await iosShare.folders());
};

const uriOf = (path: string): string => `file://${path}`;
const pathOf = (uri: string): string => decodeURIComponent(uri.replace(/^file:\/\//, "")).replace(/\/$/, "");

/** All files access on Android. Scoped storage lists the top folders even without it, so Android is asked when it can say. */
export const hasFullStorage = (): boolean => {
  if (Platform.OS !== "android") return false;
  const granted = androidShare?.fullStorage?.() ?? null;
  if (granted !== null) return granted;
  try {
    new Directory(uriOf(STORAGE)).list();
    return true;
  } catch {
    return false;
  }
};

export const askFullStorage = (): Promise<void> => Linking.sendIntent("android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION").catch(() => Linking.openSettings());

/** Android without All files access, where only Downloads › Vitals is shared. Never on iPhone. */
const limitedStorage = (): boolean => Platform.OS === "android" && !hasFullStorage();

/** `limitedStorage`, checked again each time Vitals comes back from Android's settings. */
export const useLimitedStorage = (): boolean => {
  const [limited, setLimited] = useState(limitedStorage);
  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => state === "active" && setLimited(limitedStorage()));
    return () => subscription.remove();
  }, []);
  return limited;
};

/** The sharing switch. On Android, turning it on also asks for All files access, without which only Downloads › Vitals is shared. */
export const shareThisPhone = (on: boolean): void => {
  setShareFiles(on);
  if (on && limitedStorage()) void askFullStorage();
};

const FOLDER_PLACE: Readonly<Record<SharedFolder["role"], FsRoot["place"]>> = { downloads: "downloads", documents: "documents", other: "folder" };

/** What this phone shares. On iPhone that's Files › Vitals, plus Photos and picked folders when given. */
export const phoneRoots = (photos = sharePhotos.get(), folders = sharedFolders.get(), full = hasFullStorage()): ReadonlyArray<FsRoot> => {
  if (Platform.OS === "ios") {
    return [
      { label: "Files › Vitals", path: pathOf(Paths.document.uri), place: "folder" },
      ...(photos ? [{ label: "Photos", path: PHOTOS, place: "photos" } satisfies FsRoot] : []),
      ...folders.map((folder): FsRoot => ({ label: folder.name, path: folder.path, place: FOLDER_PLACE[folder.role] })),
    ];
  }
  if (!full) return [{ label: "Downloads › Vitals", path: `${STORAGE}/Download/Vitals`, place: "downloads" }];
  return [
    { label: "Phone storage", path: STORAGE, place: "storage" },
    { label: "Downloads", path: `${STORAGE}/Download`, place: "downloads" },
    { label: "Camera", path: `${STORAGE}/DCIM`, place: "photos" },
    { label: "Pictures", path: `${STORAGE}/Pictures`, place: "pictures" },
    { label: "Movies", path: `${STORAGE}/Movies`, place: "movies" },
    { label: "Music", path: `${STORAGE}/Music`, place: "music" },
    { label: "Documents", path: `${STORAGE}/Documents`, place: "documents" },
  ];
};

const inside = (path: string, roots: ReadonlyArray<FsRoot>): boolean => roots.some((root) => path === root.path || path.startsWith(`${root.path}/`));

const isPhoto = (path: string): boolean => path.startsWith(`${PHOTOS}/`);

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

const byName = (left: FsEntry, right: FsEntry): number => (left.kind === "folder" ? 0 : 1) - (right.kind === "folder" ? 0 : 1) || collator.compare(left.name, right.name);

const newest = (left: FsEntry, right: FsEntry): number => right.modifiedAt - left.modifiedAt || byName(left, right);

const SORTS: Readonly<Record<FsSort, (left: FsEntry, right: FsEntry) => number>> = {
  name: byName,
  date: newest,
  size: (left, right) => right.size - left.size || byName(left, right),
};

const entryOf = (item: Directory | File, dir: string): FsEntry | null => {
  try {
    const info = item.info();
    if (!info.exists) return null;
    const name = item.name;
    const folder = item instanceof Directory;
    return { name, path: `${dir}/${name}`, kind: folder ? "folder" : "file", size: folder ? 0 : Math.max(0, info.size ?? 0), modifiedAt: Math.max(0, Math.round(info.modificationTime ?? 0)) };
  } catch {
    return null;
  }
};

const nativeEntry = (entry: NativeEntry): FsEntry => ({ name: entry.name, path: entry.path, kind: "file", size: Math.max(0, Math.round(entry.size)), modifiedAt: Math.max(0, Math.round(entry.modifiedAt)) });

const walk = (dir: string, prefix: string, out: Array<OutgoingFile>): void => {
  for (const item of new Directory(uriOf(dir)).list()) {
    if (out.length > SEND_LIMIT) return;
    if (item.name.startsWith(".")) continue;
    if (item instanceof Directory) walk(`${dir}/${item.name}`, `${prefix}/${item.name}`, out);
    else out.push({ uri: item.uri, name: item.name, path: prefix, size: Math.max(0, item.size), mime: null });
  }
};

/** Every visible file under `dir`, a few levels deep and a few thousand at most. */
const filesUnder = (dir: string, depth: number, out: Array<FsEntry>): void => {
  let items: ReadonlyArray<Directory | File>;
  try {
    items = new Directory(uriOf(dir)).list();
  } catch {
    return;
  }
  for (const item of items) {
    if (out.length >= WALK_LIMIT) return;
    if (item.name.startsWith(".")) continue;
    if (item instanceof Directory) {
      if (depth > 0) filesUnder(`${dir}/${item.name}`, depth - 1, out);
      continue;
    }
    const entry = entryOf(item, dir);
    if (entry !== null) out.push(entry);
  }
};

const KIND_WORD: Readonly<Record<FsRecentKind, string>> = { photos: "Photos", screenshots: "Screenshots", downloads: "Downloads", documents: "Documents" };

export class PhoneShare {
  private readonly remote: Remote;
  private roots: ReadonlyArray<FsRoot> = [];
  private stop: (() => void) | null = null;
  private readonly cache = new Map<string, { readonly at: number; readonly entries: ReadonlyArray<FsEntry> }>();
  private readonly name = deviceInfo().name;

  constructor(remote: Remote) {
    this.remote = remote;
  }

  start(roots: ReadonlyArray<FsRoot> = phoneRoots()): void {
    if (this.stop !== null) return;
    this.roots = roots;
    this.stop = this.remote.connection.watch(
      (client) => client["fs.serve"]({ roots, recent: true }),
      (request) => void this.answer(request),
    );
  }

  stopServing(): void {
    this.stop?.();
    this.stop = null;
    this.cache.clear();
  }

  private async answer(request: FsServeRequest): Promise<void> {
    let result: FsServeResult | null = null;
    let error: string | null = null;
    try {
      result = await this.handle(request);
    } catch (cause) {
      error = cause instanceof Error ? cause.message : "This phone couldn't do that";
    }
    await this.remote.connection.call((client) => client["fs.reply"]({ id: request.id, result, error: error === null ? null : error.slice(0, 500) }));
  }

  private async handle(request: FsServeRequest): Promise<FsServeResult> {
    switch (request._tag) {
      case "List":
        return { _tag: "List", result: await this.list(request.path, request.sort, request.offset, request.limit) };
      case "Thumbs":
        return { _tag: "Thumbs", thumbs: await Promise.all(request.paths.map((path) => this.thumb(path))) };
      case "Send": {
        const files = await this.collect(request.paths);
        const drop = await this.remote.drops.send(files, request.relay === null ? {} : { relay: request.relay });
        if (drop === null) throw new Error("This phone couldn't start sending");
        return { _tag: "Send", files: files.length };
      }
      case "Recent":
        return { _tag: "Recent", result: await this.recent(request.kind, request.offset, Math.min(request.limit, FS_LIMITS.recent)) };
    }
  }

  private allowed(path: string): void {
    if (!inside(path, this.roots) || path.split("/").includes("..")) throw new Error("This phone doesn't share that folder");
  }

  private async list(path: string, sort: FsSort, offset: number, limit: number): Promise<FsListResult> {
    this.allowed(path);
    if (path === PHOTOS && iosShare !== null) {
      const page = await iosShare.photos("all", offset, limit);
      return { path, parent: null, entries: page.entries.map(nativeEntry), total: page.total };
    }
    const entries = this.entries(path);
    const sorted = [...entries].sort(SORTS[sort]);
    const parent = path.slice(0, path.lastIndexOf("/"));
    return { path, parent: this.roots.some((root) => root.path === path) || !inside(parent, this.roots) ? null : parent, entries: sorted.slice(offset, offset + limit), total: sorted.length };
  }

  private entries(path: string): ReadonlyArray<FsEntry> {
    const cached = this.cache.get(path);
    if (cached !== undefined && Date.now() - cached.at < CACHE_MS) return cached.entries;
    const entries = new Directory(uriOf(path))
      .list()
      .filter((item) => !item.name.startsWith("."))
      .map((item) => entryOf(item, path))
      .filter((entry) => entry !== null);
    this.cache.set(path, { at: Date.now(), entries });
    return entries;
  }

  /** Newest files of one kind. Only what this phone already shares: anything outside the roots is dropped. */
  private async recent(kind: FsRecentKind, offset: number, limit: number): Promise<FsRecentResult> {
    const page = await this.recentPage(kind, offset, limit);
    return { kind, entries: page.entries.map(nativeEntry).filter((entry) => inside(entry.path, this.roots)), more: page.more };
  }

  private async recentPage(kind: FsRecentKind, offset: number, limit: number): Promise<NativePage> {
    if (iosShare !== null) {
      if (kind === "photos" || kind === "screenshots") {
        if (!sharePhotos.get()) throw new Error(`${this.name} doesn't share Photos. Turn it on there in Settings › This phone.`);
        return iosShare.photos(kind, offset, limit);
      }
      const folder = sharedFolders.get().find((item) => item.role === kind);
      if (folder === undefined) throw new Error(`${this.name} doesn't share a ${KIND_WORD[kind]} folder yet. Pick one there in Settings › This phone.`);
      return this.newestIn(folder.path, offset, limit);
    }
    if (androidShare === null || !hasFullStorage()) throw new Error(`${this.name} needs All files access. Turn it on there in Settings › This phone.`);
    if (kind === "downloads") return this.newestIn(`${STORAGE}/Download`, offset, limit);
    return androidShare.recent(kind, offset, limit);
  }

  private newestIn(dir: string, offset: number, limit: number): NativePage {
    const key = `recent:${dir}`;
    const cached = this.cache.get(key);
    let entries = cached !== undefined && Date.now() - cached.at < CACHE_MS ? cached.entries : null;
    if (entries === null) {
      const found: Array<FsEntry> = [];
      filesUnder(dir, WALK_DEPTH, found);
      entries = found.sort(newest);
      this.cache.set(key, { at: Date.now(), entries });
    }
    return { entries: entries.slice(offset, offset + limit), more: entries.length > offset + limit };
  }

  private async thumb(path: string): Promise<FsThumb> {
    try {
      this.allowed(path);
      const native = androidShare ?? iosShare;
      if (native !== null && (isPhoto(path) || MEDIA.test(path))) return { path, jpeg: await native.thumbnail(path, FS_LIMITS.thumbPixels) };
      if (!IMAGE.test(path)) return { path, jpeg: null };
      const file = new File(uriOf(path));
      return { path, jpeg: file.size > 0 && file.size <= THUMB_BYTES && /\.jpe?g$/i.test(path) ? file.base64Sync() : null };
    } catch {
      return { path, jpeg: null };
    }
  }

  private async collect(paths: ReadonlyArray<string>): Promise<ReadonlyArray<OutgoingFile>> {
    for (const path of paths) this.allowed(path);
    const ios = iosShare;
    const photos = ios === null ? [] : paths.filter(isPhoto);
    const exported = ios === null ? [] : await Promise.all(photos.map((path) => ios.exportPhoto(path)));
    const out: Array<OutgoingFile> = exported.map((photo) => ({ uri: photo.uri, name: photo.name, path: null, size: Math.max(0, Math.round(photo.size)), mime: null }));
    const exportedPaths = new Set(photos);
    for (const path of paths) {
      if (exportedPaths.has(path)) continue;
      const name = path.slice(path.lastIndexOf("/") + 1);
      const directory = new Directory(uriOf(path));
      if (directory.exists) walk(path, name, out);
      else {
        const file = new File(uriOf(path));
        out.push({ uri: file.uri, name, path: null, size: Math.max(0, file.size), mime: null });
      }
      if (out.length > SEND_LIMIT) throw new Error(`That's more than ${SEND_LIMIT.toLocaleString()} files. Pick fewer.`);
    }
    return out;
  }
}
