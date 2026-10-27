import type { Connection, VitalsClient } from "@vitals/client-runtime";
import { Store } from "@vitals/client-runtime";
import {
  type DeviceId,
  type FsDevice,
  type FsDevicesResult,
  type FsEntry,
  type FsListResult,
  type FsPulled,
  type FsRecentKind,
  type FsRecentResult,
  type FsRootsResult,
  type FsSearchResult,
  type FsSort,
  FS_LIMITS,
} from "@vitals/contracts";
import type * as Effect from "effect/Effect";

export const FILES_PAGE = 200;

const THUMB_DELAY_MS = 60;
const THUMB_KEEP = 600;
const SEARCH_LIMIT = 100;

const PREVIEWABLE = /\.(jpe?g|png|gif|heic|heif|webp|tiff?|bmp|svg|pdf|mov|mp4|m4v|avi|mkv|key|pages|numbers|psd|ai)$/i;

export const hasPreview = (entry: FsEntry): boolean => entry.kind === "file" && PREVIEWABLE.test(entry.name);

/** Where a thumbnail lives in `MacFiles.thumbs`. Phone paths are keyed by device, since two phones can share a path. */
export const thumbKey = (path: string, device?: DeviceId): string => (device === undefined ? path : `${device}:${path}`);

export type Outcome<A> = { readonly ok: true; readonly value: A } | { readonly ok: false; readonly message: string };

/** The device files are on: a phone, or the Mac when `device` is null. */
export interface FsSource {
  readonly device: DeviceId | null;
  readonly name: string;
}

/** Where a copy can go: the phone in your hand, the Mac, or another phone. */
export type Destination = { readonly _tag: "Here" } | { readonly _tag: "Mac" } | { readonly _tag: "Phone"; readonly device: FsDevice };

/** Every place files on `from` (null for the Mac) can be copied to. Never the device they are already on. */
export const destinationsFor = (from: DeviceId | null, me: DeviceId, phones: ReadonlyArray<FsDevice>): ReadonlyArray<Destination> => [
  ...(from === me ? [] : [{ _tag: "Here" } as const]),
  ...(from === null ? [] : [{ _tag: "Mac" } as const]),
  ...phones.filter((phone) => phone.deviceId !== from && phone.deviceId !== me).map((device) => ({ _tag: "Phone", device }) as const),
];

export interface RecentPage {
  readonly entries: ReadonlyArray<FsEntry>;
  readonly more: boolean;
}

/**
 * Newest-first pages of several kinds as one newest-first list, each file once. It stops where the first
 * unfinished page stops, so loading more only ever adds below. `behind` are the pages to load next.
 */
export const mergeNewest = (pages: ReadonlyArray<RecentPage>): { readonly entries: ReadonlyArray<FsEntry>; readonly behind: ReadonlySet<number> } => {
  const last = (page: RecentPage): number => page.entries.at(-1)?.modifiedAt ?? Number.POSITIVE_INFINITY;
  const cutoff = Math.max(Number.NEGATIVE_INFINITY, ...pages.filter((page) => page.more).map(last));
  return {
    entries: [...new Map(pages.flatMap((page) => page.entries.map((entry) => [entry.path, entry] as const))).values()]
      .filter((entry) => entry.modifiedAt >= cutoff)
      .sort((left, right) => right.modifiedAt - left.modifiedAt),
    behind: new Set(pages.flatMap((page, index) => (page.more && last(page) >= cutoff ? [index] : []))),
  };
};

export class MacFiles {
  readonly thumbs = new Store<ReadonlyMap<string, string | null>>(new Map());
  /** The other phones, as `devices()` last listed them. */
  readonly phones = new Store<ReadonlyArray<FsDevice>>([]);
  private readonly connection: Connection;
  private readonly wanted = new Set<string>();
  private timer: ReturnType<typeof setTimeout> | null = null;
  private fetching = false;
  private device: DeviceId | undefined = undefined;

  constructor(connection: Connection) {
    this.connection = connection;
  }

  roots(device?: DeviceId): Promise<Outcome<FsRootsResult>> {
    return this.run((client) => client["fs.roots"](device === undefined ? {} : { device }));
  }

  async devices(): Promise<Outcome<FsDevicesResult>> {
    const outcome = await this.run((client) => client["fs.devices"]({}));
    if (outcome.ok) this.phones.set(outcome.value.devices);
    return outcome;
  }

  list(path: string, sort: FsSort, offset: number, device?: DeviceId): Promise<Outcome<FsListResult>> {
    return this.run((client) => client["fs.list"]({ path, sort, hidden: false, offset, limit: FILES_PAGE, ...(device === undefined ? {} : { device }) }));
  }

  pull(device: DeviceId, paths: ReadonlyArray<string>): Promise<Outcome<FsPulled>> {
    return this.run((client) => client["fs.pull"]({ device, paths }));
  }

  search(query: string): Promise<Outcome<FsSearchResult>> {
    return this.run((client) => client["fs.search"]({ query, limit: SEARCH_LIMIT }));
  }

  open(path: string): Promise<Outcome<unknown>> {
    return this.run((client) => client["fs.open"]({ path }));
  }

  /** Copies `paths` from `device` (the Mac when unset) to `to` (the Mac when null). Files never move off their device. */
  transfer(paths: ReadonlyArray<string>, to: DeviceId | null, device?: DeviceId): Promise<Outcome<FsPulled>> {
    return this.run((client) => client["fs.transfer"]({ paths, to, ...(device === undefined ? {} : { device }) }));
  }

  /** Newest photos, screenshots, downloads or documents on the Mac, or on `device` when set. */
  recent(kind: FsRecentKind, offset: number, limit: number, device?: DeviceId): Promise<Outcome<FsRecentResult>> {
    return this.run((client) => client["fs.recent"]({ kind, offset, limit, ...(device === undefined ? {} : { device }) }));
  }

  want(entries: ReadonlyArray<FsEntry>, device?: DeviceId): void {
    if (device !== undefined && device !== this.device) {
      this.wanted.clear();
      this.device = device;
    }
    if (device === undefined && this.device !== undefined) {
      this.wanted.clear();
      this.device = undefined;
    }
    const known = this.thumbs.get();
    for (const entry of entries) if (hasPreview(entry) && !known.has(thumbKey(entry.path, device))) this.wanted.add(entry.path);
    if (this.wanted.size === 0 || this.timer !== null) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      void this.fetchThumbs();
    }, THUMB_DELAY_MS);
  }

  dispose(): void {
    if (this.timer !== null) clearTimeout(this.timer);
    this.wanted.clear();
  }

  private async fetchThumbs(): Promise<void> {
    if (this.fetching) return;
    this.fetching = true;
    while (this.wanted.size > 0) {
      const batch = [...this.wanted].slice(0, FS_LIMITS.thumbs);
      for (const path of batch) this.wanted.delete(path);
      const device = this.device;
      const result = await this.connection.call((client) => client["fs.thumbs"](device === undefined ? { paths: batch } : { paths: batch, device }));
      if (!result.ok) break;
      this.thumbs.update((previous) => {
        const next = new Map(previous);
        for (const thumb of result.value.thumbs) next.set(thumbKey(thumb.path, device), thumb.jpeg === null ? null : `data:image/jpeg;base64,${thumb.jpeg}`);
        for (const key of next.keys()) {
          if (next.size <= THUMB_KEEP) break;
          next.delete(key);
        }
        return next;
      });
    }
    this.fetching = false;
  }

  private async run<A, E extends { readonly message: string }>(call: (client: VitalsClient) => Effect.Effect<A, E>): Promise<Outcome<A>> {
    const result = await this.connection.call(call);
    return result.ok ? { ok: true, value: result.value } : { ok: false, message: result.error.message };
  }
}
