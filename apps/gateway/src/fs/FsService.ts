import type { Dirent, Stats } from "node:fs";
import { appendFile, lstat, mkdir, readdir, realpath, rename, rm, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { createHash } from "node:crypto";
import { basename, dirname, extname, join, relative } from "node:path";

import {
  type DeviceId,
  type DropOffered,
  type FsDevicesResult,
  type FsPulled,
  type FsReplyInput,
  type FsRootsInput,
  type FsServeInput,
  type FsServeRequest,
  type FsServeResult,
  type FsAccess,
  type FsEntry,
  type FsKind,
  type FsListInput,
  type FsListResult,
  type FsPathInput,
  type FsPathsInput,
  type FsReadInput,
  type FsReadResult,
  type FsRecentInput,
  type FsRecentKind,
  type FsRecentResult,
  type FsRoot,
  type FsRootsResult,
  type FsSearchInput,
  type FsSearchResult,
  type FsSort,
  type FsThumbsInput,
  type FsThumbsResult,
  type FsTransferInput,
  type MacDropFile,
  CommandRejected,
  FS_LIMITS,
  Unavailable,
} from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Context from "effect/Context";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Bridge, ask } from "../bridge/Bridge.ts";
import { GatewayConfig } from "../config.ts";
import { type DropCaller, DropStore } from "../drop/DropStore.ts";
import { Store } from "../persistence/Store.ts";
import { Connections } from "../ws/Connections.ts";

type FsError = Unavailable | CommandRejected;

export class FsService extends Context.Service<
  FsService,
  {
    readonly roots: (input: FsRootsInput) => Effect.Effect<FsRootsResult, FsError>;
    readonly devices: (except: DeviceId | null) => Effect.Effect<FsDevicesResult>;
    readonly serve: (caller: DropCaller, input: FsServeInput) => Stream.Stream<FsServeRequest>;
    readonly reply: (caller: DropCaller, input: FsReplyInput) => Effect.Effect<void>;
    readonly pull: (relay: DeviceId | null, input: FsPathsInput) => Effect.Effect<FsPulled, FsError>;
    readonly list: (input: FsListInput) => Effect.Effect<FsListResult, FsError>;
    readonly search: (input: FsSearchInput) => Effect.Effect<FsSearchResult, FsError>;
    readonly thumbs: (input: FsThumbsInput) => Effect.Effect<FsThumbsResult, FsError>;
    readonly get: (caller: DropCaller, input: FsPathsInput) => Effect.Effect<DropOffered, FsError>;
    readonly open: (input: FsPathInput) => Effect.Effect<void, FsError>;
    readonly recent: (input: FsRecentInput) => Effect.Effect<FsRecentResult, FsError>;
    readonly transfer: (caller: DropCaller, input: FsTransferInput) => Effect.Effect<FsPulled, FsError>;
    readonly read: (input: FsReadInput) => Effect.Effect<FsReadResult, FsError>;
    /** Copies a phone's file into `<data dir>/preview` and returns where, for Quick Look on the Mac. */
    readonly preview: (device: DeviceId, path: string) => Effect.Effect<string, FsError>;
    readonly destination: (path: string) => Effect.Effect<string, FsError>;
  }
>()("@vitals/gateway/FsService") {}

const FOLDERS: ReadonlyArray<readonly [string, FsRoot["place"]]> = [
  ["Desktop", "desktop"],
  ["Documents", "documents"],
  ["Downloads", "downloads"],
  ["Pictures", "pictures"],
];

const PACKAGES = new Set([".app", ".bundle", ".framework", ".photoslibrary", ".musiclibrary", ".tvlibrary", ".pkg", ".rtfd", ".key", ".pages", ".numbers", ".xcodeproj", ".xcworkspace", ".xcarchive", ".playground", ".sparsebundle", ".band", ".logicx", ".fcpbundle", ".imovielibrary"]);

const CHANNEL_DIRS = [".vitals", ".vitals-nightly", ".vitals-dev"];
const CACHE_MS = 5_000;
const CACHE_DIRS = 16;
const THUMB_CACHE = 512;
const STAT_BATCH = 128;
const SEARCH_MS = 4_000;
const PHONE_TIMEOUT = "15 seconds";
const RECENT_MS = 10_000;
const RECENT_SCAN = 5_000;
const RECENT_WINDOW = "kMDItemFSContentChangeDate >= $time.today(-365)";
const DOCUMENT_TYPES = [
  "com.adobe.pdf",
  "public.presentation",
  "public.spreadsheet",
  "org.openxmlformats.wordprocessingml.document",
  "com.microsoft.word.doc",
  "com.apple.iwork.pages.sections",
  "com.apple.iwork.pages.pages",
  "public.rtf",
  "org.idpf.epub-container",
];

/** Spotlight queries for each kind the Mac answers from its index. Downloads is a plain folder listing. */
const SPOTLIGHT: Readonly<Record<Exclude<FsRecentKind, "downloads">, string>> = {
  screenshots: `(kMDItemIsScreenCapture == 1 || kMDItemFSName == "Screenshot*"c || kMDItemFSName == "Screen Shot*"c || kMDItemFSName == "CleanShot*"c) && ${RECENT_WINDOW}`,
  photos: `kMDItemContentTypeTree == "public.image" && kMDItemIsScreenCapture != 1 && ${RECENT_WINDOW}`,
  documents: `(${DOCUMENT_TYPES.map((type) => `kMDItemContentTypeTree == "${type}"`).join(" || ")}) && ${RECENT_WINDOW}`,
};

const answers = <Tag extends FsServeResult["_tag"]>(tag: Tag, result: FsServeResult): result is Extract<FsServeResult, { readonly _tag: Tag }> => result._tag === tag;

interface Server {
  readonly name: string;
  readonly roots: ReadonlyArray<FsRoot>;
  readonly recent: boolean;
  readonly read: boolean;
  readonly push: (request: FsServeRequest) => void;
}

const rejected = (message: string) => new CommandRejected({ message });
const unavailable = (message: string) => new Unavailable({ message });

const codeOf = (error: unknown): string | null =>
  typeof error === "object" && error !== null && "code" in error && typeof error.code === "string" ? error.code : null;

const failure = (error: unknown): FsError => {
  const code = codeOf(error);
  if (code === "ENOENT" || code === "ENOTDIR") return unavailable("That's no longer on your Mac");
  if (code === "EACCES" || code === "EPERM") return rejected("macOS kept Vitals out of this. Allow Full Disk Access for Vitals in System Settings › Privacy & Security.");
  if (code === "EEXIST") return rejected("Something with that name is already there");
  return unavailable("Your Mac couldn't do that");
};

const attempt = <A>(run: () => Promise<A>): Effect.Effect<A, FsError> => Effect.tryPromise({ try: run, catch: failure });

const inside = (path: string, base: string): boolean => path === base || path.startsWith(base === "/" ? "/" : `${base}/`);

const kindOf = (path: string, info: Stats, link: boolean): FsKind => {
  if (link) return "link";
  if (!info.isDirectory()) return "file";
  return PACKAGES.has(extname(path).toLowerCase()) ? "package" : "folder";
};

const entryOf = (path: string, info: Stats, link: boolean): FsEntry => {
  const kind = kindOf(path, info, link);
  return { name: basename(path) || path, path, kind, size: kind === "file" ? info.size : 0, modifiedAt: Math.max(0, Math.round(info.mtimeMs)) };
};

const statEntry = async (path: string): Promise<FsEntry | null> => {
  const info = await lstat(path).catch(() => null);
  if (info === null) return null;
  return entryOf(path, info, info.isSymbolicLink());
};

const inBatches = async <A, B>(items: ReadonlyArray<A>, run: (item: A) => Promise<B>): Promise<Array<B>> => {
  const out: Array<B> = [];
  for (let start = 0; start < items.length; start += STAT_BATCH) out.push(...(await Promise.all(items.slice(start, start + STAT_BATCH).map(run))));
  return out;
};

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

const byName = (left: FsEntry, right: FsEntry): number => {
  const leftFolder = left.kind === "folder" ? 0 : 1;
  const rightFolder = right.kind === "folder" ? 0 : 1;
  return leftFolder - rightFolder || collator.compare(left.name, right.name);
};

const SORTS: Record<FsSort, (left: FsEntry, right: FsEntry) => number> = {
  name: byName,
  date: (left, right) => right.modifiedAt - left.modifiedAt || byName(left, right),
  size: (left, right) => right.size - left.size || byName(left, right),
};

const hiddenName = (name: string): boolean => name.startsWith(".");

const hiddenPath = (path: string, base: string): boolean => relative(base, path).split("/").some(hiddenName);

const inPackage = (path: string): boolean => path.split("/").slice(0, -1).some((part) => PACKAGES.has(extname(part).toLowerCase()));

const exists = (path: string): Promise<boolean> =>
  stat(path).then(
    () => true,
    () => false,
  );

class Lru<V> {
  private readonly map = new Map<string, V>();
  private readonly size: number;

  constructor(size: number) {
    this.size = size;
  }

  get(key: string): V | undefined {
    const value = this.map.get(key);
    if (value === undefined) return undefined;
    this.map.delete(key);
    this.map.set(key, value);
    return value;
  }

  set(key: string, value: V): void {
    this.map.delete(key);
    this.map.set(key, value);
    if (this.map.size > this.size) {
      const oldest = this.map.keys().next();
      if (!oldest.done) this.map.delete(oldest.value);
    }
  }

  clear(): void {
    this.map.clear();
  }
}

export const layer = Layer.effect(
  FsService,
  Effect.gen(function* () {
    const config = yield* GatewayConfig;
    const bridge = yield* Bridge;
    const drops = yield* DropStore;
    const activity = yield* ActivityLog;
    const store = yield* Store;
    const connections = yield* Connections;
    const servers = new Map<string, Server>();
    const waiting = new Map<string, { readonly deviceId: string; readonly done: Deferred.Deferred<FsServeResult, FsError> }>();
    const homeDir = config.homeDir ?? homedir();
    const home = yield* Effect.promise(() => realpath(homeDir).catch(() => homeDir));
    const denied = yield* Effect.promise(() =>
      Promise.all(
        [config.dataDir, dirname(config.dataDir), ...CHANNEL_DIRS.map((name) => join(home, name)), join(home, "Library", "Keychains")].map((path) => realpath(path).catch(() => path)),
      ),
    );
    const library = join(home, "Library");
    let access: FsAccess = "folders";
    const listings = new Lru<{ readonly at: number; readonly entries: ReadonlyArray<FsEntry> }>(CACHE_DIRS);
    const thumbCache = new Lru<{ readonly modifiedAt: number; readonly jpeg: string | null }>(THUMB_CACHE);
    const recents = new Map<FsRecentKind, { readonly at: number; readonly entries: ReadonlyArray<FsEntry> }>();

    const log = (kind: string, caller: DropCaller, data: Record<string, unknown>) =>
      activity.record({ at: Date.now(), source: "gateway", level: "info", kind, deviceId: caller.deviceId, data });

    const folderRoots = async (): Promise<Array<FsRoot>> => {
      const found = await Promise.all(
        FOLDERS.map(async ([label, place]) => {
          const path = join(home, label);
          return (await exists(path)) ? { label, path: await realpath(path).catch(() => path), place } : null;
        }),
      );
      return found.filter((root) => root !== null);
    };

    const volumeRoots = async (): Promise<Array<FsRoot>> => {
      const names = await readdir("/Volumes").catch(() => []);
      const volumes = await Promise.all(
        names.map(async (name) => {
          const path = join("/Volumes", name);
          const real = await realpath(path).catch(() => null);
          return real === null || real === "/" ? null : { label: name, path: real, place: "volume" as const };
        }),
      );
      return volumes.filter((root) => root !== null);
    };

    const currentRoots = async (): Promise<Array<FsRoot>> => {
      const folders = await folderRoots();
      if (access === "folders") return folders;
      return [{ label: "Home", path: home, place: "home" }, ...folders, { label: "Macintosh HD", path: "/", place: "disk" }, ...(await volumeRoots())];
    };

    const shared = async (path: string): Promise<boolean> => {
      if (denied.some((base) => inside(path, base))) return false;
      if (access === "everything") return true;
      return (await folderRoots()).some((root) => inside(path, root.path));
    };

    const resolve = (path: string) =>
      Effect.gen(function* () {
        const real = yield* attempt(() => realpath(path));
        if (!(yield* Effect.promise(() => shared(real)))) return yield* Effect.fail(rejected("Your Mac doesn't share that folder"));
        return real;
      });

    const readListing = async (dir: string, hidden: boolean): Promise<ReadonlyArray<FsEntry>> => {
      const key = `${hidden ? "1" : "0"}${dir}`;
      const cached = listings.get(key);
      if (cached !== undefined && Date.now() - cached.at < CACHE_MS) return cached.entries;
      const dirents: Array<Dirent> = await readdir(dir, { withFileTypes: true });
      const visible = hidden ? dirents : dirents.filter((dirent) => !hiddenName(dirent.name));
      const entries = (await inBatches(visible, (dirent) => statEntry(join(dir, dirent.name)))).filter((entry) => entry !== null);
      listings.set(key, { at: Date.now(), entries });
      return entries;
    };

    const parentOf = async (dir: string): Promise<string | null> => {
      if (dir === "/") return null;
      if ((await currentRoots()).some((root) => root.path === dir)) return null;
      const parent = dirname(dir);
      return (await shared(parent)) ? parent : null;
    };

    const askPhone = <Tag extends FsServeResult["_tag"]>(device: DeviceId, request: (id: string) => Extract<FsServeRequest, { readonly _tag: Tag }>) =>
      Effect.gen(function* () {
        const server = servers.get(device);
        const name = store.device(device)?.name ?? "That device";
        if (server === undefined) return yield* Effect.fail(unavailable(`${name} isn't open. Open Vitals on it to browse.`));
        const sent = request(newId());
        if (sent._tag === "Recent" && !server.recent) return yield* Effect.fail(rejected(`Update Vitals on ${name} to see its recent files`));
        if (sent._tag === "Read" && !server.read) return yield* Effect.fail(rejected(`Update Vitals on ${name} to preview its files`));
        const done = yield* Deferred.make<FsServeResult, FsError>();
        const id = sent.id;
        waiting.set(id, { deviceId: device, done });
        server.push(sent);
        const result = yield* Deferred.await(done).pipe(
          Effect.timeoutOrElse({ duration: PHONE_TIMEOUT, orElse: () => Effect.fail(unavailable(`${name} didn't answer. Keep Vitals open on it.`)) }),
          Effect.ensuring(Effect.sync(() => waiting.delete(id))),
        );
        if (!answers(sent._tag, result)) return yield* Effect.fail(unavailable(`${name} sent back the wrong answer`));
        return result;
      });

    const serve = (caller: DropCaller, input: FsServeInput): Stream.Stream<FsServeRequest> =>
      Stream.callback<FsServeRequest>((queue) =>
        Effect.acquireRelease(
          Effect.sync(() => {
            const server: Server = { name: caller.name, roots: input.roots, recent: input.recent === true, read: input.read === true, push: (request) => Queue.offerUnsafe(queue, request) };
            servers.set(caller.deviceId, server);
            return server;
          }),
          (server) =>
            Effect.sync(() => {
              if (servers.get(caller.deviceId) === server) servers.delete(caller.deviceId);
            }),
        ),
      );

    const reply = (caller: DropCaller, input: FsReplyInput) =>
      Effect.suspend(() => {
        const entry = waiting.get(input.id);
        if (entry === undefined || entry.deviceId !== caller.deviceId) return Effect.void;
        return (input.result === null ? Deferred.fail(entry.done, rejected(input.error ?? "That device couldn't do it")) : Deferred.succeed(entry.done, input.result)).pipe(Effect.asVoid);
      });

    const devices = (except: DeviceId | null) =>
      Effect.map(connections.connectedDevices, (connected) => ({
        devices: store
          .devices()
          .filter((device) => device.platform !== "web" && device.id !== except && device.scopes.includes("files"))
          .map((device) => ({ deviceId: device.id, name: device.name, platform: device.platform, online: servers.has(device.id), connected: connected.has(device.id) })),
      }));

    const pull = (relay: DeviceId | null, input: FsPathsInput) =>
      Effect.gen(function* () {
        if (input.device === undefined) return yield* Effect.fail(rejected("Pick a device to get files from"));
        const answer = yield* askPhone(input.device, (id) => ({ _tag: "Send", id, paths: input.paths, relay }));
        return { files: answer.files };
      });

    const listMac = (input: FsListInput) =>
      Effect.gen(function* () {
        const dir = yield* resolve(input.path);
        const entries = yield* attempt(() => readListing(dir, input.hidden));
        const sorted = [...entries].sort(SORTS[input.sort]);
        return {
          path: dir,
          parent: yield* Effect.promise(() => parentOf(dir)),
          entries: sorted.slice(input.offset, input.offset + input.limit),
          total: sorted.length,
        } satisfies FsListResult;
      });

    const mdfind = async (query: string, within: ReadonlyArray<string>, limit: number): Promise<{ readonly paths: ReadonlyArray<string>; readonly truncated: boolean }> => {
      const results = await Promise.all(
        within.map(async (root) => {
          const proc = Bun.spawn(["/usr/bin/mdfind", "-onlyin", root, "-name", query], { stdout: "pipe", stderr: "ignore" });
          const timer = setTimeout(() => proc.kill(), SEARCH_MS);
          const text = await new Response(proc.stdout).text().catch(() => "");
          clearTimeout(timer);
          return text
            .split("\n")
            .filter((line) => line.length > 0 && !hiddenPath(line, root));
        }),
      );
      const unique = [...new Set(results.flat())];
      return { paths: unique.slice(0, limit), truncated: unique.length > limit };
    };

    const search = (input: FsSearchInput) =>
      Effect.gen(function* () {
        const roots = yield* Effect.promise(currentRoots);
        const within = access === "everything" ? [home, ...roots.filter((root) => root.place === "volume").map((root) => root.path)] : roots.map((root) => root.path);
        const found = yield* Effect.promise(() => mdfind(input.query, within, input.limit * 2));
        const allowed = yield* Effect.promise(async () => {
          const checks = await Promise.all(found.paths.map(async (path) => ((await shared(path)) ? path : null)));
          return checks.filter((path) => path !== null);
        });
        const entries = yield* Effect.promise(() => inBatches(allowed.slice(0, input.limit), statEntry));
        return { entries: entries.filter((entry) => entry !== null), truncated: found.truncated || allowed.length > input.limit } satisfies FsSearchResult;
      });

    const list = (input: FsListInput) =>
      input.device === undefined
        ? listMac(input)
        : askPhone(input.device, (id) => ({ _tag: "List", id, path: input.path, sort: input.sort, offset: input.offset, limit: input.limit })).pipe(Effect.map((answer) => answer.result));

    const thumbs = (input: FsThumbsInput) =>
      input.device === undefined
        ? thumbsMac(input)
        : askPhone(input.device, (id) => ({ _tag: "Thumbs", id, paths: input.paths })).pipe(Effect.map((answer) => ({ thumbs: answer.thumbs })));

    const thumbsMac = (input: FsThumbsInput) =>
      Effect.gen(function* () {
        const known = yield* Effect.promise(() =>
          Promise.all(
            input.paths.map(async (path) => {
              const real = await realpath(path).catch(() => null);
              if (real === null || !(await shared(real))) return { path, real: null, modifiedAt: 0 };
              const info = await stat(real).catch(() => null);
              return { path, real, modifiedAt: info === null ? 0 : Math.round(info.mtimeMs) };
            }),
          ),
        );
        const missing = known.filter((item) => item.real !== null && thumbCache.get(item.real)?.modifiedAt !== item.modifiedAt);
        if (missing.length > 0) {
          const reply = yield* ask(bridge, { _tag: "FsThumbs", paths: missing.flatMap((item) => (item.real === null ? [] : [item.real])), pixels: FS_LIMITS.thumbPixels }, "20 seconds").pipe(
            Effect.orElseSucceed(() => ({ _tag: "FsThumbs" as const, thumbs: [] })),
          );
          const byPath = new Map(reply.thumbs.map((thumb) => [thumb.path, thumb.jpeg]));
          for (const item of missing) if (item.real !== null) thumbCache.set(item.real, { modifiedAt: item.modifiedAt, jpeg: byPath.get(item.real) ?? null });
        }
        return { thumbs: known.map((item) => ({ path: item.path, jpeg: item.real === null ? null : (thumbCache.get(item.real)?.jpeg ?? null) })) } satisfies FsThumbsResult;
      });

    const tooMany = () => Object.assign(new Error("too many"), { code: "ETOOMANY" });

    const expand = async (real: string, out: Array<MacDropFile>): Promise<void> => {
      const info = await stat(real);
      if (!info.isDirectory()) {
        if (out.length >= FS_LIMITS.pull) throw tooMany();
        out.push({ name: basename(real), path: null, size: info.size, mime: null, origin: real });
        return;
      }
      const top = basename(real);
      const walk = async (dir: string): Promise<void> => {
        const folder = relative(real, dir);
        for (const dirent of await readdir(dir, { withFileTypes: true })) {
          const origin = join(dir, dirent.name);
          if (denied.some((base) => inside(origin, base))) continue;
          if (dirent.isDirectory()) await walk(origin);
          else if (dirent.isFile()) {
            if (out.length >= FS_LIMITS.pull) throw tooMany();
            out.push({ name: dirent.name, path: folder === "" ? top : join(top, folder), size: 0, mime: null, origin });
          }
        }
      };
      await walk(real);
    };

    const collect = (paths: ReadonlyArray<string>) =>
      Effect.gen(function* () {
        const reals = yield* Effect.forEach(paths, resolve);
        const found: Array<MacDropFile> = [];
        yield* Effect.tryPromise({
          try: () => reals.reduce((chain, real) => chain.then(() => expand(real, found)), Promise.resolve()),
          catch: (error) => (codeOf(error) === "ETOOMANY" ? rejected(`That's more than ${FS_LIMITS.pull.toLocaleString("en-US")} files. Pick fewer.`) : failure(error)),
        });
        if (found.length === 0) return yield* Effect.fail(rejected("Nothing to send in there"));
        return yield* Effect.promise(() => inBatches(found, async (file) => ({ ...file, size: file.size || ((await lstat(file.origin).catch(() => null))?.size ?? 0) })));
      });

    const get = (caller: DropCaller, input: FsPathsInput) =>
      Effect.gen(function* () {
        const files = yield* collect(input.paths);
        const offered = yield* drops.pull(caller, files);
        log("fs.get", caller, { items: input.paths.length, files: files.length, bytes: offered.drop.bytes });
        return offered;
      });

    const open = ({ path }: FsPathInput) =>
      Effect.gen(function* () {
        const real = yield* resolve(path);
        yield* ask(bridge, { _tag: "FsOpen", path: real });
      });

    const spotlight = async (query: string, within: ReadonlyArray<string>): Promise<ReadonlyArray<string>> => {
      const found = await Promise.all(
        within.map(async (root) => {
          const proc = Bun.spawn(["/usr/bin/mdfind", "-onlyin", root, query], { stdout: "pipe", stderr: "ignore" });
          const timer = setTimeout(() => proc.kill(), SEARCH_MS);
          const text = await new Response(proc.stdout).text().catch(() => "");
          clearTimeout(timer);
          return text.split("\n").filter((line) => line.length > 0 && !hiddenPath(line, root) && !inPackage(line));
        }),
      );
      return [...new Set(found.flat())].slice(0, RECENT_SCAN);
    };

    const recentPaths = async (kind: FsRecentKind): Promise<ReadonlyArray<string>> => {
      const roots = await folderRoots();
      if (kind !== "downloads") return spotlight(SPOTLIGHT[kind], roots.map((root) => root.path));
      const downloads = roots.find((root) => root.place === "downloads");
      if (downloads === undefined) return [];
      return (await readListing(downloads.path, false)).filter((entry) => entry.kind === "file").map((entry) => entry.path);
    };

    const recentMac = (input: FsRecentInput) =>
      Effect.gen(function* () {
        const cached = recents.get(input.kind);
        const entries =
          cached !== undefined && Date.now() - cached.at < RECENT_MS
            ? cached.entries
            : yield* Effect.promise(async () => {
                const paths = (await Promise.all((await recentPaths(input.kind)).map(async (path) => ((await shared(path)) ? path : null)))).filter((path) => path !== null);
                const found = (await inBatches(paths, statEntry)).filter((entry): entry is FsEntry => entry !== null && entry.kind === "file");
                const sorted = found.sort((left, right) => right.modifiedAt - left.modifiedAt);
                recents.set(input.kind, { at: Date.now(), entries: sorted });
                return sorted;
              });
        return { kind: input.kind, entries: entries.slice(input.offset, input.offset + input.limit), more: entries.length > input.offset + input.limit } satisfies FsRecentResult;
      });

    const transfer = (caller: DropCaller, input: FsTransferInput) =>
      Effect.gen(function* () {
        if (input.device === undefined) {
          if (input.to === null) return yield* Effect.fail(rejected("Those files are already on your Mac"));
          const target = store.device(input.to);
          if (target === null || target.revokedAt !== null) return yield* Effect.fail(rejected("That device isn't paired with your Mac"));
          const files = yield* collect(input.paths);
          yield* drops.send(input.to, files);
          log("fs.transfer", caller, { items: input.paths.length, files: files.length, to: input.to });
          return { files: files.length };
        }
        if (input.to === input.device) return yield* Effect.fail(rejected("Those files are already there"));
        return yield* pull(input.to, { device: input.device, paths: input.paths });
      });

    const readMac = (input: FsReadInput) =>
      Effect.gen(function* () {
        const real = yield* resolve(input.path);
        const info = yield* attempt(() => stat(real));
        if (!info.isFile()) return yield* Effect.fail(rejected("Only files can be previewed"));
        const end = Math.min(info.size, input.offset + input.length);
        const bytes = input.offset >= info.size ? new ArrayBuffer(0) : yield* attempt(() => Bun.file(real).slice(input.offset, end).arrayBuffer());
        return { data: Buffer.from(bytes).toString("base64"), offset: input.offset, total: info.size, done: end >= info.size } satisfies FsReadResult;
      });

    const read = (input: FsReadInput) =>
      input.device === undefined
        ? readMac(input)
        : askPhone(input.device, (id) => ({ _tag: "Read", id, path: input.path, offset: input.offset, length: input.length })).pipe(Effect.map((answer) => answer.result));

    const previews = join(config.dataDir, "preview");
    yield* Effect.promise(() => rm(previews, { recursive: true, force: true }));

    const preview = (device: DeviceId, path: string) =>
      Effect.gen(function* () {
        const dir = join(previews, `${createHash("sha256").update(`${device}\0${path}`).digest("hex").slice(0, 16)}-${newId()}`);
        const target = join(dir, basename(path) || "file");
        const partial = `${target}.part`;
        yield* attempt(() => mkdir(dir, { recursive: true }));
        let offset = 0;
        for (;;) {
          const chunk = yield* read({ device, path, offset, length: FS_LIMITS.readChunk });
          if (chunk.total > FS_LIMITS.previewBytes) return yield* Effect.fail(rejected("That file is too big to preview. Transfer it instead."));
          const bytes = Buffer.from(chunk.data, "base64");
          yield* attempt(() => appendFile(partial, bytes));
          offset += bytes.length;
          if (chunk.done || bytes.length === 0) break;
        }
        yield* attempt(async () => {
          if (offset === 0) await appendFile(partial, new Uint8Array(0));
          await rename(partial, target);
        });
        return target;
      });

    const recent = (input: FsRecentInput) =>
      input.device === undefined
        ? recentMac(input)
        : askPhone(input.device, (id) => ({ _tag: "Recent", id, kind: input.kind, offset: input.offset, limit: input.limit })).pipe(Effect.map((answer) => answer.result));

    const destination = (path: string) =>
      Effect.gen(function* () {
        const real = yield* resolve(path);
        const info = yield* attempt(() => stat(real));
        if (!info.isDirectory()) return yield* Effect.fail(rejected("That isn't a folder"));
        const hidden = inside(real, home) && relative(home, real).split("/").some((part) => part.startsWith("."));
        if (!(inside(real, home) || inside(real, "/Volumes")) || real === home || hidden || inside(real, library)) return yield* Effect.fail(rejected("Vitals can't put files there"));
        return real;
      });

    const inbox = yield* bridge.subscribe;
    yield* Stream.fromSubscription(inbox).pipe(
      Stream.runForEach((message) =>
        Effect.sync(() => {
          if (message.t !== "fsPolicy" || message.access === access) return;
          access = message.access;
          listings.clear();
          recents.clear();
        }),
      ),
      Effect.forkScoped,
    );

    return FsService.of({
      roots: (input) =>
        input.device === undefined
          ? Effect.promise(async () => ({ roots: await currentRoots() }))
          : Effect.suspend(() => {
              const server = servers.get(input.device ?? "");
              return server === undefined
                ? Effect.fail(unavailable(`${store.device(input.device ?? "")?.name ?? "That device"} isn't open. Open Vitals on it to browse.`))
                : Effect.succeed({ roots: server.roots });
            }),
      devices,
      serve,
      reply,
      pull,
      list,
      search,
      thumbs,
      get,
      open,
      recent,
      transfer,
      read,
      preview,
      destination,
    });
  }),
);
