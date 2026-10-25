import { Store } from "@vitals/client-runtime";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import type { OutgoingFile } from "@vitals/app/state/drops.ts";
import type { FsEntry, FsListResult, FsRoot, FsServeRequest, FsServeResult, FsSort, FsThumb } from "@vitals/contracts";
import { Directory, File, Paths } from "expo-file-system";
import * as SecureStore from "expo-secure-store";
import { Linking, Platform } from "react-native";

const KEY = "vitals.remote.shareFiles";
const STORAGE = "/storage/emulated/0";
const CACHE_MS = 5_000;
const THUMB_BYTES = 400_000;
const SEND_LIMIT = 2_000;
const IMAGE = /\.(jpe?g|png|gif|webp|heic|heif)$/i;

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

const uriOf = (path: string): string => `file://${path}`;
const pathOf = (uri: string): string => decodeURIComponent(uri.replace(/^file:\/\//, "")).replace(/\/$/, "");

export const hasFullStorage = (): boolean => {
  if (Platform.OS !== "android") return false;
  try {
    new Directory(uriOf(STORAGE)).list();
    return true;
  } catch {
    return false;
  }
};

export const askFullStorage = (): Promise<void> => Linking.sendIntent("android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION").catch(() => Linking.openSettings());

export const phoneRoots = (): ReadonlyArray<FsRoot> => {
  if (Platform.OS === "ios") return [{ label: "Files › Vitals", path: pathOf(Paths.document.uri), place: "folder" }];
  if (!hasFullStorage()) return [{ label: "Downloads › Vitals", path: `${STORAGE}/Download/Vitals`, place: "downloads" }];
  return [
    { label: "Phone storage", path: STORAGE, place: "storage" },
    { label: "Downloads", path: `${STORAGE}/Download`, place: "downloads" },
    { label: "Camera", path: `${STORAGE}/DCIM`, place: "photos" },
    { label: "Pictures", path: `${STORAGE}/Pictures`, place: "pictures" },
    { label: "Movies", path: `${STORAGE}/Movies`, place: "movies" },
    { label: "Documents", path: `${STORAGE}/Documents`, place: "documents" },
  ];
};

const inside = (path: string, roots: ReadonlyArray<FsRoot>): boolean => roots.some((root) => path === root.path || path.startsWith(`${root.path}/`));

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

const byName = (left: FsEntry, right: FsEntry): number => (left.kind === "folder" ? 0 : 1) - (right.kind === "folder" ? 0 : 1) || collator.compare(left.name, right.name);

const SORTS: Readonly<Record<FsSort, (left: FsEntry, right: FsEntry) => number>> = {
  name: byName,
  date: (left, right) => right.modifiedAt - left.modifiedAt || byName(left, right),
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

const walk = (dir: string, prefix: string, out: Array<OutgoingFile>): void => {
  for (const item of new Directory(uriOf(dir)).list()) {
    if (out.length > SEND_LIMIT) return;
    if (item.name.startsWith(".")) continue;
    if (item instanceof Directory) walk(`${dir}/${item.name}`, `${prefix}/${item.name}`, out);
    else out.push({ uri: item.uri, name: item.name, path: prefix, size: Math.max(0, item.size), mime: null });
  }
};

export class PhoneShare {
  private readonly remote: Remote;
  private roots: ReadonlyArray<FsRoot> = [];
  private stop: (() => void) | null = null;
  private readonly cache = new Map<string, { readonly at: number; readonly entries: ReadonlyArray<FsEntry> }>();

  constructor(remote: Remote) {
    this.remote = remote;
  }

  start(): void {
    if (this.stop !== null) return;
    this.roots = phoneRoots();
    const roots = this.roots;
    this.stop = this.remote.connection.watch(
      (client) => client["fs.serve"]({ roots }),
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
        return { _tag: "List", result: this.list(request.path, request.sort, request.offset, request.limit) };
      case "Thumbs":
        return { _tag: "Thumbs", thumbs: request.paths.map((path) => this.thumb(path)) };
      case "Send": {
        const files = this.collect(request.paths);
        const drop = await this.remote.drops.send(files, request.relay === null ? {} : { relay: request.relay });
        if (drop === null) throw new Error("This phone couldn't start sending");
        return { _tag: "Send", files: files.length };
      }
    }
  }

  private allowed(path: string): void {
    if (!inside(path, this.roots) || path.split("/").includes("..")) throw new Error("This phone doesn't share that folder");
  }

  private list(path: string, sort: FsSort, offset: number, limit: number): FsListResult {
    this.allowed(path);
    const cached = this.cache.get(path);
    const entries =
      cached !== undefined && Date.now() - cached.at < CACHE_MS
        ? cached.entries
        : new Directory(uriOf(path))
            .list()
            .filter((item) => !item.name.startsWith("."))
            .map((item) => entryOf(item, path))
            .filter((entry) => entry !== null);
    this.cache.set(path, { at: Date.now(), entries });
    const sorted = [...entries].sort(SORTS[sort]);
    const parent = path.slice(0, path.lastIndexOf("/"));
    return { path, parent: this.roots.some((root) => root.path === path) || !inside(parent, this.roots) ? null : parent, entries: sorted.slice(offset, offset + limit), total: sorted.length };
  }

  private thumb(path: string): FsThumb {
    if (!IMAGE.test(path) || !inside(path, this.roots)) return { path, jpeg: null };
    try {
      const file = new File(uriOf(path));
      return { path, jpeg: file.size > 0 && file.size <= THUMB_BYTES && /\.jpe?g$/i.test(path) ? file.base64Sync() : null };
    } catch {
      return { path, jpeg: null };
    }
  }

  private collect(paths: ReadonlyArray<string>): ReadonlyArray<OutgoingFile> {
    const out: Array<OutgoingFile> = [];
    for (const path of paths) {
      this.allowed(path);
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
