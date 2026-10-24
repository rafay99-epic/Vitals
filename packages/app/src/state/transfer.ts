import { Store } from "@vitals/client-runtime";
import {
  CLIP_LIMITS,
  type Clip,
  type ClipChunk,
  type ClipId,
  type ClipSendBegin,
  type ClipSendBegun,
  type ClipSendChunk,
  type ClipSendFinish,
  type ClipsReadInput,
} from "@vitals/contracts";

/** What one RPC came back with. Same shape as `Connection.call`, so its results pass straight in. */
export type Reply<A> =
  | { readonly ok: true; readonly value: A }
  | { readonly ok: false; readonly error: { readonly _tag: string; readonly message: string } };

/** The clip RPCs a transfer needs, plus a way to wait for the Mac to come back. */
export interface ClipLink {
  readonly read: (input: ClipsReadInput) => Promise<Reply<ClipChunk>>;
  readonly begin: (input: ClipSendBegin) => Promise<Reply<ClipSendBegun>>;
  readonly chunk: (input: ClipSendChunk) => Promise<Reply<{ readonly received: number }>>;
  readonly finish: (input: ClipSendFinish) => Promise<Reply<Clip>>;
  /** Calls `ready` once the Mac is connected (at once if it already is). Returns a function that stops waiting. */
  readonly whenOnline: (ready: () => void) => () => void;
}

/** Bytes to send, read a piece at a time. Platform code backs it with a file (native) or a Blob (web). */
export interface ByteSource {
  readonly size: number;
  /** Base64 of `length` bytes starting at `offset`. May be called with several reads in flight. */
  readonly read: (offset: number, length: number) => Promise<string>;
  readonly close?: () => void;
}

/** Where downloaded bytes go. Chunks can arrive in any order. */
export interface ByteSink {
  readonly write: (offset: number, base64: string) => Promise<void>;
  readonly finish: () => Promise<void>;
  /** Drops what was written after a cancel or a failure. */
  readonly abort: () => void;
}

export type Phase = "running" | "waiting" | "done" | "failed" | "cancelled";

export interface Progress {
  readonly done: number;
  readonly total: number;
  readonly phase: Phase;
  readonly error: string | null;
}

/** Up to this many chunk calls run at once. */
export const IN_FLIGHT = 4;

/** A dropped connection fails calls with these. The call is retried once the Mac is back. */
const RETRYABLE: ReadonlySet<string> = new Set(["NotConnected", "RpcClientError"]);

/** Pause before retrying, so a connection that is still tearing down can't spin the loop. */
const RETRY_PAUSE_MS = 500;

/** Thrown inside a transfer to unwind every worker once it is cancelled or has failed. */
class Stopped extends Error {}

/** Raw size of a base64 string. */
export const byteLength = (base64: string): number => {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return Math.max(0, Math.floor((base64.length * 3) / 4) - padding);
};

/** Start offset of every chunk in a `total`-byte item. */
export const chunkOffsets = (total: number, size: number = CLIP_LIMITS.chunkBytes): ReadonlyArray<number> =>
  Array.from({ length: Math.ceil(total / size) }, (_, index) => index * size);

/** 0 to 1. An item with no bytes counts as complete once it is done. */
export const fraction = ({ done, total, phase }: Progress): number => (total === 0 ? (phase === "done" ? 1 : 0) : Math.min(1, done / total));

/**
 * One transfer (a download, or a batch of uploads) with live progress and Cancel.
 * Calls dropped by a lost connection wait for the Mac and retry the same chunk, so a transfer
 * resumes from the chunks the Mac already confirmed. Anything else the Mac answers fails it.
 */
export class Transfer {
  readonly progress: Store<Progress>;
  private readonly stops = new Set<() => void>();

  constructor(
    readonly label: string,
    total: number,
    private readonly link: ClipLink,
    private readonly tuning: { readonly inFlight?: number; readonly pauseMs?: number } = {},
  ) {
    this.progress = new Store<Progress>({ done: 0, total, phase: "running", error: null });
  }

  get stopped(): boolean {
    const phase = this.progress.get().phase;
    return phase === "done" || phase === "failed" || phase === "cancelled";
  }

  cancel(): void {
    this.end("cancelled", null);
  }

  /** Marks the transfer finished. Only the first ending counts. */
  end(phase: "done" | "failed" | "cancelled", error: string | null): void {
    if (this.stopped) return;
    this.progress.update((current) => ({ ...current, phase, error }));
    for (const stop of this.stops) stop();
    this.stops.clear();
  }

  setTotal(total: number): void {
    this.progress.update((current) => ({ ...current, total }));
  }

  advance(bytes: number): void {
    if (bytes === 0) return;
    this.progress.update((current) => ({ ...current, done: current.done + bytes }));
  }

  private phase(phase: "running" | "waiting"): void {
    if (this.stopped || this.progress.get().phase === phase) return;
    this.progress.update((current) => ({ ...current, phase }));
  }

  /** Resolves once the Mac is reachable, or throws `Stopped` if the transfer ends first. */
  private online(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      let settled = false;
      let stopWaiting: (() => void) | null = null;
      const finish = () => {
        settled = true;
        clearTimeout(timer);
        stopWaiting?.();
        this.stops.delete(onStop);
      };
      const onStop = () => {
        finish();
        reject(new Stopped());
      };
      const timer = setTimeout(() => {
        const stop = this.link.whenOnline(() => {
          if (settled) return;
          finish();
          resolve();
        });
        if (settled) stop();
        else stopWaiting = stop;
      }, this.tuning.pauseMs ?? RETRY_PAUSE_MS);
      this.stops.add(onStop);
    });
  }

  /** Runs one call until it lands, waiting out dropped connections. */
  async call<A>(run: () => Promise<Reply<A>>): Promise<A> {
    while (true) {
      if (this.stopped) throw new Stopped();
      const reply = await run();
      if (this.stopped) throw new Stopped();
      if (reply.ok) {
        this.phase("running");
        return reply.value;
      }
      if (!RETRYABLE.has(reply.error._tag)) {
        this.end("failed", reply.error.message);
        throw new Stopped();
      }
      this.phase("waiting");
      await this.online();
    }
  }

  /** Runs `step` for every offset, `inFlight` at a time. `step` returns the bytes it confirmed. */
  async pump(offsets: ReadonlyArray<number>, step: (offset: number) => Promise<number>): Promise<void> {
    let next = 0;
    const worker = async () => {
      while (!this.stopped) {
        const offset = offsets[next];
        if (offset === undefined) return;
        next += 1;
        this.advance(await step(offset));
      }
    };
    const results = await Promise.allSettled(Array.from({ length: Math.min(this.tuning.inFlight ?? IN_FLIGHT, offsets.length) }, worker));
    const failed = results.find((result) => result.status === "rejected");
    if (failed !== undefined) throw failed.reason;
    if (this.stopped) throw new Stopped();
  }
}

/** Runs `body`, turning the stop signal into `null` and any other throw into a failed transfer. */
const settle = async <A>(transfer: Transfer, body: () => Promise<A>): Promise<A | null> => {
  try {
    const value = await body();
    transfer.end("done", null);
    return value;
  } catch (cause) {
    if (!(cause instanceof Stopped)) transfer.end("failed", cause instanceof Error ? cause.message : "Something went wrong");
    return null;
  }
};

/**
 * Downloads one clip into `sink`. The first chunk goes alone, because the Mac may need a moment to
 * clone or zip a file first and the reply tells us the real size; the rest run four at a time.
 * Resolves true once the sink is finished, false on cancel or failure (the sink is aborted then).
 */
export const downloadClip = async (transfer: Transfer, link: ClipLink, id: ClipId, sink: ByteSink): Promise<boolean> => {
  const chunkBytes = CLIP_LIMITS.chunkBytes;
  /** Reads `[offset, end)` fully, in case the Mac answers with shorter pieces than asked for. */
  const fill = async (offset: number, end: number): Promise<number> => {
    let at = offset;
    while (at < end) {
      const chunk = await transfer.call(() => link.read({ id, offset: at }));
      const size = byteLength(chunk.data);
      if (size === 0) break;
      await sink.write(at, chunk.data);
      at += size;
    }
    return at - offset;
  };
  const done = await settle(transfer, async () => {
    const first = await transfer.call(() => link.read({ id, offset: 0 }));
    transfer.setTotal(first.total);
    const firstSize = byteLength(first.data);
    if (firstSize > 0) await sink.write(0, first.data);
    transfer.advance(firstSize);
    const rest = first.done ? 0 : Math.min(chunkBytes, first.total) - firstSize;
    if (rest > 0) transfer.advance(await fill(firstSize, firstSize + rest));
    const offsets = chunkOffsets(first.total, chunkBytes).slice(1);
    await transfer.pump(offsets, (offset) => fill(offset, Math.min(first.total, offset + chunkBytes)));
    await sink.finish();
    return true;
  });
  if (done === null) sink.abort();
  return done === true;
};

/** Something to send. Text and links travel inline; images and files come from a source. */
export type Outgoing =
  | { readonly kind: "text" | "link"; readonly text: string }
  | { readonly kind: "image" | "file"; readonly name: string; readonly mime: string | null; readonly sha256: string | null; readonly source: ByteSource };

/** Bytes an item puts on the wire, for progress. */
export const outgoingBytes = (item: Outgoing): number => ("source" in item ? item.source.size : 0);

/** Uploads one item, then returns the clip the Mac stored. Throws `Stopped` on cancel or failure. */
const uploadOne = async (transfer: Transfer, link: ClipLink, item: Outgoing): Promise<Clip> => {
  if (!("source" in item)) {
    const begun = await transfer.call(() => link.begin({ kind: item.kind, name: null, mime: null, bytes: 0, sha256: null, text: item.text }));
    if (begun.clip !== null) return begun.clip;
    return transfer.call(() => link.finish({ uploadId: begun.uploadId }));
  }
  const { source } = item;
  const begun = await transfer.call(() => link.begin({ kind: item.kind, name: item.name, mime: item.mime, bytes: source.size, sha256: item.sha256, text: null }));
  if (begun.clip !== null) {
    transfer.advance(source.size);
    return begun.clip;
  }
  await transfer.pump(chunkOffsets(source.size), async (offset) => {
    const length = Math.min(CLIP_LIMITS.chunkBytes, source.size - offset);
    const data = await source.read(offset, length);
    await transfer.call(() => link.chunk({ uploadId: begun.uploadId, offset, data }));
    return length;
  });
  return transfer.call(() => link.finish({ uploadId: begun.uploadId }));
};

/** Uploads items one after another under one progress bar. Resolves the stored clips, or null on cancel or failure. */
export const uploadAll = async (transfer: Transfer, link: ClipLink, items: ReadonlyArray<Outgoing>): Promise<ReadonlyArray<Clip> | null> => {
  const clips = await settle(transfer, async () => {
    const stored: Array<Clip> = [];
    // One item at a time on purpose: its chunks already fill the four slots, and the Mac caps open uploads per device.
    for (const item of items) stored.push(await uploadOne(transfer, link, item));
    return stored;
  });
  for (const item of items) if ("source" in item) item.source.close?.();
  return clips;
};
