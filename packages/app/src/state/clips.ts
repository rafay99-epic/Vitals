import { type Connection, Store } from "@vitals/client-runtime";
import { CLIP_LIMITS, type Clip, type ClipDestination, type ClipEvent, type ClipId } from "@vitals/contracts";

import { type ByteSink, type ClipLink, downloadClip, type Outgoing, outgoingBytes, Transfer, uploadAll } from "./transfer.ts";

/** A removed clip stays undoable this long before the Mac deletes it. Outlasts the 4 s toast. */
const UNDO_MS = 5_000;

/** A running download or upload, for the progress card and strip. */
export interface Moving {
  readonly id: number;
  readonly direction: "up" | "down";
  readonly transfer: Transfer;
}

/** A started transfer and how it ended: the value, or null on cancel or failure. */
export interface Started<A> {
  readonly transfer: Transfer;
  readonly result: Promise<A | null>;
}

const newestFirst = (left: Clip, right: Clip): number => right.at - left.at;

const upsert = (clips: ReadonlyArray<Clip>, clip: Clip): ReadonlyArray<Clip> => [clip, ...clips.filter((item) => item.id !== clip.id)].sort(newestFirst);

const batches = <A>(items: ReadonlyArray<A>, size: number): ReadonlyArray<ReadonlyArray<A>> =>
  Array.from({ length: Math.ceil(items.length / size) }, (_, index) => items.slice(index * size, (index + 1) * size));

const pad = (value: number) => String(value).padStart(2, "0");

/** "Sent 2026-10-24 at 22.41": a Finder-safe folder name for one batch of files. */
export const sentFolder = (at: Date): string =>
  `Sent ${String(at.getFullYear())}-${pad(at.getMonth() + 1)}-${pad(at.getDate())} at ${pad(at.getHours())}.${pad(at.getMinutes())}`;

/**
 * The Mac's clipboard history and every transfer to or from it, shared by the phone and web apps.
 * History streams over `clips.watch` once the Mac says it supports clips (`Hello.clips`) and this
 * device holds the `clipboard` scope. Sending needs only `operate`, so it works without history.
 */
export class MacClips {
  /** The Mac serves `clips.*`. Older Macs keep the plain text clipboard. null until first connected. */
  readonly supported = new Store<boolean | null>(null);
  /** History is on in Vitals on the Mac. null until the first snapshot arrives. */
  readonly enabled = new Store<boolean | null>(null);
  /** Days the Mac keeps unpinned clips, once it has said. */
  readonly keepDays = new Store<number | null>(null);
  /** Newest first. */
  readonly clips = new Store<ReadonlyArray<Clip>>([]);
  readonly moving = new Store<ReadonlyArray<Moving>>([]);
  readonly link: ClipLink;
  private readonly added = new Set<(clip: Clip) => void>();
  private readonly removing = new Map<ClipId, ReturnType<typeof setTimeout>>();
  private readonly stops: Array<() => void> = [];
  private nextId = 0;

  constructor(
    private readonly connection: Connection,
    private readonly report: (message: string) => void,
  ) {
    this.link = {
      read: (input) => connection.call((client) => client["clips.read"](input)),
      begin: (input) => connection.call((client) => client["clips.send.begin"](input)),
      chunk: (input) => connection.call((client) => client["clips.send.chunk"](input)),
      finish: (input) => connection.call((client) => client["clips.send.finish"](input)),
      whenOnline: (ready) => {
        if (connection.state.get()._tag === "Ready") {
          ready();
          return () => {};
        }
        const stop = connection.state.subscribe(() => {
          if (connection.state.get()._tag !== "Ready") return;
          stop();
          ready();
        });
        return stop;
      },
    };
    // The watch reconnects on its own, so it starts once: the first time a connection allows it.
    let watching = false;
    this.stops.push(
      connection.state.subscribe(() => {
        const state = connection.state.get();
        if (state._tag !== "Ready") return;
        const supported = state.hello.clips === true;
        this.supported.set(supported);
        if (watching || !supported || !state.hello.scopes.includes("clipboard")) return;
        watching = true;
        this.stops.push(connection.watch((client) => client["clips.watch"]({}), (event) => this.apply(event)));
      }),
    );
  }

  /** Calls `listener` for each copy made on the Mac while this app is connected, repeats included. Not for the snapshot. */
  onAdded(listener: (clip: Clip) => void): () => void {
    this.added.add(listener);
    return () => {
      this.added.delete(listener);
    };
  }

  apply(event: ClipEvent): void {
    switch (event._tag) {
      case "Snapshot":
        this.enabled.set(event.enabled);
        this.keepDays.set(event.keepDays);
        this.clips.set([...event.clips].filter((clip) => !this.removing.has(clip.id)).sort(newestFirst));
        break;
      case "Added":
        if (this.removing.has(event.clip.id)) return;
        this.clips.update((clips) => upsert(clips, event.clip));
        for (const listener of this.added) listener(event.clip);
        break;
      case "Updated": {
        if (this.removing.has(event.clip.id)) return;
        const before = this.clips.get().find((clip) => clip.id === event.clip.id);
        this.clips.update((clips) => upsert(clips, event.clip));
        // Copying the same thing again on the Mac comes back as an Updated clip with a newer time.
        if (event.clip.deviceId === null && before !== undefined && event.clip.at > before.at) {
          for (const listener of this.added) listener(event.clip);
        }
        break;
      }
      case "Removed": {
        const gone = new Set<string>(event.ids);
        this.clips.update((clips) => clips.filter((clip) => !gone.has(clip.id)));
        break;
      }
    }
  }

  async pin(clip: Clip, pinned: boolean): Promise<boolean> {
    const result = await this.connection.call((client) => client["clips.pin"]({ id: clip.id, pinned }));
    if (result.ok) this.clips.update((clips) => upsert(clips, result.value));
    else this.report(result.error.message);
    return result.ok;
  }

  /** Hides the clip now and deletes it on the Mac a few seconds later. Returns Undo. */
  remove(clip: Clip): () => void {
    this.clips.update((clips) => clips.filter((item) => item.id !== clip.id));
    const timer = setTimeout(() => {
      this.removing.delete(clip.id);
      void this.connection.call((client) => client["clips.remove"]({ id: clip.id })).then((result) => {
        if (result.ok) return;
        this.report(result.error.message);
        this.clips.update((clips) => upsert(clips, clip));
      });
    }, UNDO_MS);
    this.removing.set(clip.id, timer);
    return () => {
      const pending = this.removing.get(clip.id);
      if (pending === undefined) return;
      clearTimeout(pending);
      this.removing.delete(clip.id);
      this.clips.update((clips) => upsert(clips, clip));
    };
  }

  /**
   * Places stored clips on the Mac clipboard or in Downloads. Several files for Downloads land
   * together in one folder named after the moment they were sent. Resolves how many landed, or null on failure.
   */
  async put(ids: ReadonlyArray<ClipId>, to: ClipDestination): Promise<number | null> {
    let placed = 0;
    const folder = to === "downloads" && ids.length > 1 ? sentFolder(new Date()) : null;
    for (const batch of batches(ids, CLIP_LIMITS.batch)) {
      const result = await this.connection.call((client) => client["clips.put"]({ ids: batch, to, folder }));
      if (!result.ok) {
        this.report(result.error.message);
        return null;
      }
      placed += result.value.placed;
    }
    return placed;
  }

  /** Uploads items under one progress bar, then puts them on the Mac clipboard or in Downloads. Resolves the stored clips once placed. */
  send(label: string, items: ReadonlyArray<Outgoing>, to: ClipDestination): Started<ReadonlyArray<Clip>> {
    const transfer = new Transfer(label, items.reduce((sum, item) => sum + outgoingBytes(item), 0), this.link);
    const untrack = this.track("up", transfer);
    const result = uploadAll(transfer, this.link, items)
      .then(async (clips) => {
        if (clips === null) return this.reportEnd(transfer);
        for (const clip of clips) this.clips.update((current) => upsert(current, clip));
        const placed = await this.put(
          clips.map((clip) => clip.id),
          to,
        );
        return placed === null ? null : clips;
      })
      .finally(untrack);
    return { transfer, result };
  }

  /** Downloads a clip's bytes into `sink`. Resolves true once the sink has everything. */
  fetch(label: string, clip: Clip, sink: ByteSink): Started<true> {
    const transfer = new Transfer(label, clip.bytes, this.link);
    const untrack = this.track("down", transfer);
    const result = downloadClip(transfer, this.link, clip.id, sink)
      .then((done): true | null => (done ? true : this.reportEnd(transfer)))
      .finally(untrack);
    return { transfer, result };
  }

  cancelAll(): void {
    for (const moving of this.moving.get()) moving.transfer.cancel();
  }

  dispose(): void {
    for (const stop of this.stops) stop();
    for (const timer of this.removing.values()) clearTimeout(timer);
    this.removing.clear();
    this.added.clear();
    this.cancelAll();
  }

  /** Failures carry the Mac's message; a cancel is the user's own doing and needs no report. */
  private reportEnd(transfer: Transfer): null {
    const { phase, error } = transfer.progress.get();
    if (phase === "failed") this.report(error ?? "The transfer failed");
    return null;
  }

  private track(direction: Moving["direction"], transfer: Transfer): () => void {
    const entry: Moving = { id: ++this.nextId, direction, transfer };
    this.moving.update((list) => [...list, entry]);
    return () => this.moving.update((list) => list.filter((item) => item !== entry));
  }
}
