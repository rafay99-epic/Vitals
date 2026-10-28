import { Store } from "@vitals/client-runtime";
import { toBase64 } from "@vitals/app/lib/base64.ts";
import { deviceInfo } from "@vitals/app/lib/device.ts";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import type { OutgoingFile } from "@vitals/app/state/drops.ts";
import { FS_LIMITS, type FsEntry, type FsReadResult, type FsListResult, type FsRecentKind, type FsRecentResult, type FsRoot, type FsServeRequest, type FsServeResult, type FsSort, type FsThumb } from "@vitals/contracts";
import { Directory, File, FileMode, Paths } from "expo-file-system";
import * as SecureStore from "expo-secure-store";
import { useEffect, useState } from "react";
import { AppState, Linking, Platform } from "react-native";

import { androidShare, iosShare, nativeFiles, type NativeEntry, type NativePage, type PhotosAccess, type SharedFolder } from "../../modules/vitals-share/index.ts";

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

const setShareFiles = (on: boolean): void => {
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
  return probeFullStorage();
};

/**
 * Builds without the native check: another app's folder inside Download or Documents can only be
 * listed with All files access. With no such folder to try, the top of storage is the best guess.
 */
const probeFullStorage = (): boolean => {
  for (const top of ["Download", "Documents"]) {
    let folders: ReadonlyArray<Directory>;
    try {
      folders = new Directory(uriOf(`${STORAGE}/${top}`)).list().filter((item): item is Directory => item instanceof Directory && item.name !== "Vitals");
    } catch {
      return false;
    }
    for (const folder of folders.slice(0, 3)) {
      try {
        folder.list();
        return true;
      } catch {
        return false;
      }
    }
  }
  try {
    new Directory(uriOf(STORAGE)).list();
    return true;
  } catch {
    return false;
  }
};

/** When another device last asked for something only All files access would let Vitals read. 0 until then. */
export const allFilesWanted = new Store<number>(0);

/** What a caller sees when Android keeps Vitals out of a folder. This phone asks for access at the same time. */
const needsAllFiles = (what: string, cause?: unknown): Error => {
  allFilesWanted.set(Date.now());
  return new Error(`${deviceInfo().name} needs All files access ${what}. Open Vitals on it and tap Turn it on.`, { cause });
};

const readable = async <A>(read: () => A | Promise<A>): Promise<A> => {
  try {
    return await read();
  } catch (cause) {
    if (cause instanceof Error && /permission/i.test(cause.message)) throw hasFullStorage() ? new Error("Android keeps this folder to itself", { cause }) : needsAllFiles("to open this", cause);
    throw cause;
  }
};

/** Opens Vitals' own All files access switch. Builds without the native call open the list of every app instead. */
export const askFullStorage = async (): Promise<void> => {
  if (await (androidShare?.openFullStorage?.() ?? Promise.resolve(false)).catch(() => false)) return;
  await Linking.sendIntent("android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION").catch(() => Linking.openSettings());
};

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

/** Case-insensitive with numbers in order ("2" before "10"), as one plain string compare: no Intl call per comparison. */
const nameKey = (name: string): string => name.toLowerCase().replace(/\d+/g, (digits) => digits.padStart(16, "0"));

const byKey = (left: string, right: string): number => (left < right ? -1 : left > right ? 1 : 0);

/** Folders first, then by name. */
const byName = (keys: ReadonlyMap<FsEntry, string>) => (left: FsEntry, right: FsEntry): number =>
  (left.kind === "folder" ? 0 : 1) - (right.kind === "folder" ? 0 : 1) || byKey(keys.get(left) ?? "", keys.get(right) ?? "");

const SORTS: Readonly<Record<FsSort, (keys: ReadonlyMap<FsEntry, string>) => (left: FsEntry, right: FsEntry) => number>> = {
  name: byName,
  date: (keys) => {
    const name = byName(keys);
    return (left, right) => right.modifiedAt - left.modifiedAt || name(left, right);
  },
  size: (keys) => {
    const name = byName(keys);
    return (left, right) => right.size - left.size || name(left, right);
  },
};

const sorted = (entries: ReadonlyArray<FsEntry>, sort: FsSort): ReadonlyArray<FsEntry> => {
  const keys = new Map(entries.map((entry) => [entry, nameKey(entry.name)] as const));
  return [...entries].sort(SORTS[sort](keys));
};

const newest = (left: FsEntry, right: FsEntry): number => right.modifiedAt - left.modifiedAt;

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

/**
 * A folder's visible entries. Natively in one call off the JS thread when this build can; otherwise
 * through expo-file-system, one `info()` per entry. Throws `NEEDS_ALL_FILES` when Android says no.
 */
const listFolder = (dir: string): Promise<ReadonlyArray<FsEntry>> =>
  readable(async () => {
    const list = nativeFiles?.list;
    if (list === undefined) {
      return new Directory(uriOf(dir))
        .list()
        .filter((item) => !item.name.startsWith("."))
        .map((item) => entryOf(item, dir))
        .filter((entry) => entry !== null);
    }
    const { names, dirs, sizes, times } = await list(dir);
    return names.map((name, index): FsEntry => {
      const folder = dirs[index] === true;
      return { name, path: `${dir}/${name}`, kind: folder ? "folder" : "file", size: folder ? 0 : Math.max(0, Math.round(sizes[index] ?? 0)), modifiedAt: Math.max(0, Math.round(times[index] ?? 0)) };
    });
  });

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
const filesUnder = async (dir: string, depth: number, out: Array<FsEntry>): Promise<void> => {
  let items: ReadonlyArray<FsEntry>;
  try {
    items = await listFolder(dir);
  } catch {
    return;
  }
  for (const item of items) {
    if (out.length >= WALK_LIMIT) return;
    if (item.kind !== "folder") out.push(item);
    else if (depth > 0) await filesUnder(item.path, depth - 1, out);
  }
};

const KIND_WORD: Readonly<Record<FsRecentKind, string>> = { photos: "Photos", screenshots: "Screenshots", downloads: "Downloads", documents: "Documents" };

export class PhoneShare {
  private readonly remote: Remote;
  private roots: ReadonlyArray<FsRoot> = [];
  private stop: (() => void) | null = null;
  private readonly cache = new Map<string, { readonly at: number; readonly entries: ReadonlyArray<FsEntry> }>();
  private readonly name = deviceInfo().name;
  private readonly exports = new Map<string, string>();

  constructor(remote: Remote) {
    this.remote = remote;
  }

  /** `limited` tells the other devices Android hasn't allowed All files access yet. */
  start(roots: ReadonlyArray<FsRoot>, limited: boolean): void {
    if (this.stop !== null) return;
    this.roots = roots;
    this.stop = this.remote.connection.watch(
      (client) => client["fs.serve"]({ roots, recent: true, read: true, limited }),
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
      case "Read":
        return { _tag: "Read", result: await this.read(request.path, request.offset, Math.min(request.length, FS_LIMITS.readChunk)) };
    }
  }

  /** A photo exported once per preview: every chunk of it reads the same file. */
  private async exported(path: string): Promise<string> {
    const known = this.exports.get(path);
    if (known !== undefined) return known;
    if (iosShare === null) throw new Error("This phone doesn't share that");
    const { uri } = await iosShare.exportPhoto(path);
    this.exports.set(path, uri);
    return uri;
  }

  /** One chunk of a file for a preview elsewhere, read natively when this build can. Photos on iPhone are exported first, like a send. */
  private async read(path: string, offset: number, length: number): Promise<FsReadResult> {
    this.allowed(path);
    const local = isPhoto(path) ? pathOf(await this.exported(path)) : path;
    const readChunk = nativeFiles?.readChunk;
    if (readChunk !== undefined) {
      const chunk = await readable(() => readChunk(local, offset, length));
      return { data: chunk.data, offset, total: chunk.total, done: offset + chunk.read >= chunk.total };
    }
    const handle = await readable(() => new File(uriOf(local)).open(FileMode.ReadOnly));
    try {
      const total = handle.size ?? 0;
      handle.offset = Math.min(offset, total);
      const bytes = await handle.readBytes(length);
      return { data: toBase64(bytes), offset, total, done: offset + bytes.length >= total };
    } finally {
      handle.close();
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
    const entries = await this.entries(path, sort);
    const parent = path.slice(0, path.lastIndexOf("/"));
    return { path, parent: this.roots.some((root) => root.path === path) || !inside(parent, this.roots) ? null : parent, entries: entries.slice(offset, offset + limit), total: entries.length };
  }

  /** A folder listed and sorted once, then paged from the cache for a few seconds. */
  private async entries(path: string, sort: FsSort): Promise<ReadonlyArray<FsEntry>> {
    const key = `${sort}:${path}`;
    const cached = this.cache.get(key);
    if (cached !== undefined && Date.now() - cached.at < CACHE_MS) return cached.entries;
    const entries = sorted(await listFolder(path), sort);
    this.cache.set(key, { at: Date.now(), entries });
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
    if (androidShare === null || !hasFullStorage()) throw needsAllFiles(`to show its ${KIND_WORD[kind]}`);
    if (kind === "downloads") return this.newestIn(`${STORAGE}/Download`, offset, limit);
    return androidShare.recent(kind, offset, limit);
  }

  private async newestIn(dir: string, offset: number, limit: number): Promise<NativePage> {
    const key = `recent:${dir}`;
    const cached = this.cache.get(key);
    let entries = cached !== undefined && Date.now() - cached.at < CACHE_MS ? cached.entries : null;
    if (entries === null) {
      const found: Array<FsEntry> = [];
      await filesUnder(dir, WALK_DEPTH, found);
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
