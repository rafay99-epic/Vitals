import type { Connection, VitalsClient } from "@vitals/client-runtime";
import { Store } from "@vitals/client-runtime";
import { type FsEntry, type FsListResult, type FsRootsResult, type FsSearchResult, type FsSort, FS_LIMITS } from "@vitals/contracts";
import type * as Effect from "effect/Effect";

export const FILES_PAGE = 200;

const THUMB_DELAY_MS = 60;
const THUMB_KEEP = 600;
const SEARCH_LIMIT = 100;

const PREVIEWABLE = /\.(jpe?g|png|gif|heic|heif|webp|tiff?|bmp|svg|pdf|mov|mp4|m4v|avi|mkv|key|pages|numbers|psd|ai)$/i;

export const hasPreview = (entry: FsEntry): boolean => entry.kind === "file" && PREVIEWABLE.test(entry.name);

export type Outcome<A> = { readonly ok: true; readonly value: A } | { readonly ok: false; readonly message: string };

export class MacFiles {
  readonly thumbs = new Store<ReadonlyMap<string, string | null>>(new Map());
  private readonly connection: Connection;
  private readonly wanted = new Set<string>();
  private timer: ReturnType<typeof setTimeout> | null = null;
  private fetching = false;

  constructor(connection: Connection) {
    this.connection = connection;
  }

  roots(): Promise<Outcome<FsRootsResult>> {
    return this.run((client) => client["fs.roots"]({}));
  }

  list(path: string, sort: FsSort, offset: number): Promise<Outcome<FsListResult>> {
    return this.run((client) => client["fs.list"]({ path, sort, hidden: false, offset, limit: FILES_PAGE }));
  }

  search(query: string): Promise<Outcome<FsSearchResult>> {
    return this.run((client) => client["fs.search"]({ query, limit: SEARCH_LIMIT }));
  }

  open(path: string): Promise<Outcome<unknown>> {
    return this.run((client) => client["fs.open"]({ path }));
  }

  rename(path: string, name: string): Promise<Outcome<FsEntry>> {
    return this.run((client) => client["fs.rename"]({ path, name }));
  }

  folder(parent: string, name: string): Promise<Outcome<FsEntry>> {
    return this.run((client) => client["fs.folder"]({ parent, name }));
  }

  trash(paths: ReadonlyArray<string>): Promise<Outcome<{ readonly trashed: number }>> {
    return this.run((client) => client["fs.trash"]({ paths }));
  }

  want(entries: ReadonlyArray<FsEntry>): void {
    const known = this.thumbs.get();
    for (const entry of entries) if (hasPreview(entry) && !known.has(entry.path)) this.wanted.add(entry.path);
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
      const result = await this.connection.call((client) => client["fs.thumbs"]({ paths: batch }));
      if (!result.ok) break;
      this.thumbs.update((previous) => {
        const next = new Map(previous);
        for (const thumb of result.value.thumbs) next.set(thumb.path, thumb.jpeg === null ? null : `data:image/jpeg;base64,${thumb.jpeg}`);
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
