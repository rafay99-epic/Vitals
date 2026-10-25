import { type Connection, Store } from "@vitals/client-runtime";
import type { DeviceId, Drop, DropEvent, DropFile, DropId, DropTicket, LanTls } from "@vitals/contracts";
import type { DownloadJob, DropEndpoint, TransferEvent, UploadJob } from "@vitals/tailnet/drop";
import type * as Option from "effect/Option";
import * as Schema from "effect/Schema";

export interface DropEngine {
  readonly supported: boolean;
  readonly upload: (job: UploadJob) => Promise<void>;
  readonly download: (job: DownloadJob) => Promise<void>;
  readonly cancel: (job: string) => Promise<void>;
  readonly listen: (listener: (event: TransferEvent) => void) => () => void;
}

export interface Shelf {
  readonly read: (key: string) => Promise<string | null>;
  readonly write: (key: string, value: string) => void;
}

const SavedFile = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  path: Schema.NullOr(Schema.String),
  size: Schema.Number,
  mime: Schema.NullOr(Schema.String),
  uri: Schema.NullOr(Schema.String),
  at: Schema.Number,
});
export type SavedFile = typeof SavedFile.Type;

const SentDrop = Schema.Struct({
  id: Schema.String,
  label: Schema.String,
  bytes: Schema.Number,
  files: Schema.Number,
  mime: Schema.NullOr(Schema.String),
  at: Schema.Number,
});
export type SentDrop = typeof SentDrop.Type;

const Upload = Schema.Struct({ fileId: Schema.String, uri: Schema.String });
type Upload = typeof Upload.Type;
type Uploads = Readonly<Record<string, ReadonlyArray<Upload>>>;

const decodeReceived = Schema.decodeUnknownOption(Schema.fromJsonString(Schema.Array(SavedFile)));
const decodeSent = Schema.decodeUnknownOption(Schema.fromJsonString(Schema.Array(SentDrop)));
const decodeUploads = Schema.decodeUnknownOption(Schema.fromJsonString(Schema.Record(Schema.String, Schema.Array(Upload))));
const decodeFlag = Schema.decodeUnknownOption(Schema.fromJsonString(Schema.Boolean));

interface Shelved {
  readonly received: ReadonlyArray<SavedFile>;
  readonly sent: ReadonlyArray<SentDrop>;
  readonly uploads: Uploads;
  readonly autoAccept: boolean;
}

export interface OutgoingFile {
  readonly uri: string;
  readonly name: string;
  readonly path: string | null;
  readonly size: number;
  readonly mime: string | null;
}

export interface DropLive {
  readonly done: number;
  readonly total: number;
  readonly route: "lan" | "tailnet" | null;
  readonly stalled: boolean;
  readonly failed: boolean;
}

export type DropFinish =
  | { readonly _tag: "Received"; readonly drop: Drop; readonly files: ReadonlyArray<SavedFile> }
  | { readonly _tag: "Sent"; readonly drop: Drop }
  | { readonly _tag: "Declined"; readonly drop: Drop };

type JobState = "queued" | "starting" | "running" | "done" | "failed";

interface Job {
  readonly id: string;
  readonly dropId: DropId;
  readonly file: DropFile;
  readonly direction: "in" | "out";
  readonly uri: string | null;
  state: JobState;
  done: number;
  attempts: number;
  stalled: boolean;
  route: "lan" | "tailnet" | null;
}

export const PARALLEL_FILES = 2;
export const PUBLISH_MS = 250;
export const REFRESH_EARLY_MS = 5 * 60_000;
const KEEP = 200;
const RETRIES = 2;
const ENDED: ReadonlySet<Drop["state"]> = new Set(["done", "failed", "cancelled", "declined"]);

export const jobIdOf = (dropId: string, fileId: string): string => `${dropId}/${fileId}`;

export const isEnded = (drop: Drop): boolean => ENDED.has(drop.state);

export const isIncoming = (drop: Drop, me: DeviceId): boolean => drop.to._tag === "Device" && drop.to.deviceId === me;

export const isOutgoing = (drop: Drop, me: DeviceId): boolean => drop.from._tag === "Device" && drop.from.deviceId === me;

export const shouldAccept = (drop: Drop, me: DeviceId, autoAccept: boolean): boolean => autoAccept && drop.state === "asking" && drop.from._tag === "Mac" && isIncoming(drop, me);

export const nextJobs = <J extends { readonly state: JobState }>(jobs: Iterable<J>, limit = PARALLEL_FILES): ReadonlyArray<J> => {
  const all = [...jobs];
  const busy = all.filter((job) => job.state === "running" || job.state === "starting").length;
  return all.filter((job) => job.state === "queued").slice(0, Math.max(0, limit - busy));
};

export const refreshDelay = (expiresAt: number, now: number): number => Math.max(0, expiresAt - now - REFRESH_EARLY_MS);

export const ticketUsable = (ticket: DropTicket | undefined, now: number): ticket is DropTicket => ticket !== undefined && ticket.expiresAt - now > REFRESH_EARLY_MS;

const hostPart = (host: string): string => (host.includes(":") && !host.startsWith("[") ? `[${host}]` : host);

export const dropEndpoints = (input: {
  readonly hosts: ReadonlyArray<string>;
  readonly tls: LanTls | undefined;
  readonly tailnet: string | null;
  readonly builtIn: boolean;
}): ReadonlyArray<DropEndpoint> => {
  const { tls } = input;
  const lan = tls === undefined ? [] : [...new Set(input.hosts)].map((host): DropEndpoint => ({ url: `https://${hostPart(host)}:${String(tls.port)}`, pin: tls.pin, tsnet: false }));
  const tailnet = input.tailnet?.replace(/\/+$/, "") ?? null;
  if (tailnet === null) return lan;
  return [...lan, ...(input.builtIn ? [{ url: tailnet, pin: null, tsnet: true }] : []), { url: tailnet, pin: null, tsnet: false }];
};

export const folderOf = (path: string | null): string | null => {
  const folders = (path ?? "").split("/").slice(0, -1).filter((part) => part !== "");
  return folders.length === 0 ? null : folders.join("/");
};

export const fileFinished = (drop: Drop, file: DropFile): boolean => file.done >= file.size && (file.size > 0 || drop.state === "done");

export const dropLabel = (drop: Pick<Drop, "files">): string => {
  const first = drop.files[0];
  if (drop.files.length === 1 && first !== undefined) return first.name;
  const folder = first?.path?.split("/")[0];
  if (folder !== undefined && folder !== "" && drop.files.every((file) => file.path?.split("/")[0] === folder)) return folder;
  return `${String(drop.files.length)} files`;
};

const fileTitle = (job: Job): string => (job.direction === "in" ? `Getting ${job.file.name} from your Mac` : `Sending ${job.file.name} to your Mac`);

const messageOf = (error: unknown): string => (error instanceof Error ? error.message : "The transfer failed");

/**
 * Drops between this device and the Mac. Bytes move through the engine (native on phones, fetch on
 * the web); this keeps the queue, the tickets and the lists of received and sent files.
 */
export class MacDrops {
  readonly supported = new Store<boolean | null>(null);
  readonly drops = new Store<ReadonlyArray<Drop>>([]);
  readonly live = new Store<ReadonlyMap<DropId, DropLive>>(new Map());
  readonly received = new Store<ReadonlyArray<SavedFile>>([]);
  readonly sent = new Store<ReadonlyArray<SentDrop>>([]);
  readonly autoAccept = new Store<boolean>(true);
  readonly ready: Promise<void>;
  private uploads: Uploads = {};
  private readonly jobs = new Map<string, Job>();
  private readonly tickets = new Map<DropId, DropTicket>();
  private readonly ticketCalls = new Map<DropId, Promise<DropTicket | null>>();
  private readonly refreshTimers = new Map<DropId, ReturnType<typeof setTimeout>>();
  private readonly accepting = new Set<DropId>();
  private readonly unacked = new Map<string, () => Promise<boolean>>();
  private readonly reacked = new Set<string>();
  private readonly finishes = new Set<(finish: DropFinish) => void>();
  private readonly stops: Array<() => void> = [];
  private publishTimer: ReturnType<typeof setTimeout> | null = null;
  private lastPublish = 0;
  private autoAcceptChanged = false;
  private disposed = false;

  constructor(
    private readonly connection: Connection,
    private readonly engine: DropEngine,
    private readonly shelf: Shelf,
    private readonly me: DeviceId,
    private readonly endpoints: () => ReadonlyArray<DropEndpoint>,
    private readonly report: (message: string) => void,
  ) {
    this.ready = this.load();
    this.stops.push(engine.listen((event) => this.onTransfer(event)));
    let watching = false;
    this.stops.push(
      connection.state.subscribe(() => {
        const state = connection.state.get();
        if (state._tag !== "Ready") return;
        const supported = state.hello.drop === true && state.hello.scopes.includes("files");
        this.supported.set(supported);
        this.flushAcks();
        this.pump();
        if (watching || !supported || !engine.supported) return;
        watching = true;
        this.stops.push(connection.watch((client) => client["drop.watch"]({}), (event) => void this.ready.then(() => this.apply(event))));
      }),
    );
  }

  get canSend(): boolean {
    return this.engine.supported && this.supported.get() === true;
  }

  onFinish(listener: (finish: DropFinish) => void): () => void {
    this.finishes.add(listener);
    return () => {
      this.finishes.delete(listener);
    };
  }

  setAutoAccept(on: boolean): void {
    this.autoAcceptChanged = true;
    this.autoAccept.set(on);
    this.save("autoAccept", on);
    if (on) for (const drop of this.drops.get()) this.reconcile(drop);
  }

  apply(event: DropEvent): void {
    if (this.disposed) return;
    switch (event._tag) {
      case "Snapshot":
        this.drops.set(event.drops);
        for (const drop of event.drops) this.reconcile(drop);
        break;
      case "Changed":
        this.upsert(event.drop);
        this.reconcile(event.drop);
        break;
      case "Removed":
        this.drops.update((drops) => drops.filter((drop) => drop.id !== event.id));
        this.stopJobs(event.id);
        this.forget(event.id);
        break;
    }
    this.publish(true);
  }

  async send(files: ReadonlyArray<OutgoingFile>, target: { readonly dest?: string; readonly relay?: DeviceId } = {}): Promise<Drop | null> {
    if (!this.engine.supported || files.length === 0) return null;
    const offers = files.map((file) => ({ name: file.name, path: file.path, size: file.size, mime: file.mime, sha256: null }));
    const result = await this.connection.call((client) => client["drop.offer"]({ files: offers, ...target }));
    if (!result.ok) {
      this.report(result.error.message);
      return null;
    }
    const { drop, ticket } = result.value;
    this.tickets.set(drop.id, ticket);
    this.uploads = { ...this.uploads, [drop.id]: drop.files.flatMap((file, index) => (files[index] === undefined ? [] : [{ fileId: file.id, uri: files[index].uri }])) };
    this.save("uploads", this.uploads);
    this.upsert(drop);
    this.reconcile(drop);
    this.publish(true);
    return drop;
  }

  async pull(paths: ReadonlyArray<string>): Promise<Drop | null> {
    if (!this.engine.supported || paths.length === 0) return null;
    const result = await this.connection.call((client) => client["fs.get"]({ paths }));
    if (!result.ok) {
      this.report(result.error.message);
      return null;
    }
    const { drop, ticket } = result.value;
    this.tickets.set(drop.id, ticket);
    this.upsert(drop);
    this.reconcile(drop);
    this.publish(true);
    return drop;
  }

  async accept(id: DropId): Promise<boolean> {
    if (this.accepting.has(id)) return false;
    this.accepting.add(id);
    const result = await this.connection.call((client) => client["drop.accept"]({ id }));
    this.accepting.delete(id);
    if (!result.ok) {
      this.report(result.error.message);
      return false;
    }
    this.tickets.set(id, result.value.ticket);
    this.upsert(result.value.drop);
    this.reconcile(result.value.drop);
    this.publish(true);
    return true;
  }

  async decline(id: DropId): Promise<boolean> {
    const result = await this.connection.call((client) => client["drop.decline"]({ id }));
    if (!result.ok) this.report(result.error.message);
    else this.upsert(result.value);
    return result.ok;
  }

  retry(id: DropId): void {
    for (const job of this.jobs.values()) {
      if (job.dropId !== id || job.state !== "failed") continue;
      job.state = "queued";
      job.attempts = 0;
      job.stalled = false;
    }
    this.pump();
    this.publish(true);
  }

  async cancel(id: DropId): Promise<boolean> {
    this.stopJobs(id);
    const result = await this.connection.call((client) => client["drop.cancel"]({ id }));
    if (!result.ok) {
      this.report(result.error.message);
      return false;
    }
    this.upsert(result.value);
    this.reconcile(result.value);
    this.publish(true);
    return true;
  }

  forgetReceived(id: string): () => void {
    const before = this.received.get();
    this.setReceived(before.filter((file) => file.id !== id));
    return () => this.setReceived(before);
  }

  forgetSent(id: string): () => void {
    const before = this.sent.get();
    this.setSent(before.filter((drop) => drop.id !== id));
    return () => this.setSent(before);
  }

  dispose(): void {
    this.disposed = true;
    for (const stop of this.stops) stop();
    for (const job of this.jobs.values()) if (job.state === "running" || job.state === "starting") void this.engine.cancel(job.id).catch(() => undefined);
    this.jobs.clear();
    for (const timer of this.refreshTimers.values()) clearTimeout(timer);
    this.refreshTimers.clear();
    if (this.publishTimer !== null) clearTimeout(this.publishTimer);
    this.finishes.clear();
  }

  private async load(): Promise<void> {
    const [received, sent, uploads, autoAccept] = await Promise.all([
      this.read("received", decodeReceived),
      this.read("sent", decodeSent),
      this.read("uploads", decodeUploads),
      this.read("autoAccept", decodeFlag),
    ]);
    if (received !== null) this.received.set([...this.received.get(), ...received].slice(0, KEEP));
    if (sent !== null) this.sent.set([...this.sent.get(), ...sent].slice(0, KEEP));
    if (uploads !== null) this.uploads = { ...uploads, ...this.uploads };
    if (autoAccept !== null && !this.autoAcceptChanged) this.autoAccept.set(autoAccept);
  }

  private async read<A>(key: keyof Shelved, decode: (raw: unknown) => Option.Option<A>): Promise<A | null> {
    const raw = await this.shelf.read(key).catch(() => null);
    if (raw === null) return null;
    const decoded = decode(raw);
    return decoded._tag === "Some" ? decoded.value : null;
  }

  private save<K extends keyof Shelved>(key: K, value: Shelved[K]): void {
    this.shelf.write(key, JSON.stringify(value));
  }

  private setReceived(next: ReadonlyArray<SavedFile>): void {
    this.received.set(next.slice(0, KEEP));
    this.save("received", this.received.get());
  }

  private setSent(next: ReadonlyArray<SentDrop>): void {
    this.sent.set(next.slice(0, KEEP));
    this.save("sent", this.sent.get());
  }

  private upsert(drop: Drop): void {
    this.drops.update((drops) => (drops.some((item) => item.id === drop.id) ? drops.map((item) => (item.id === drop.id ? drop : item)) : [drop, ...drops]));
  }

  private reconcile(drop: Drop): void {
    if (this.disposed) return;
    const incoming = isIncoming(drop, this.me);
    const outgoing = isOutgoing(drop, this.me);
    if (!incoming && !outgoing) return;
    if (isEnded(drop)) return this.end(drop, incoming);
    if (incoming && this.engine.supported && shouldAccept(drop, this.me, this.autoAccept.get())) {
      void this.accept(drop.id);
      return;
    }
    if (drop.state !== "running") return;
    const uploads = new Map((this.uploads[drop.id] ?? []).map((upload) => [upload.fileId, upload.uri]));
    const kept = new Set(incoming ? this.received.get().map((file) => file.id) : []);
    for (const file of drop.files) {
      const id = jobIdOf(drop.id, file.id);
      if (incoming && kept.has(id)) {
        if (!this.jobs.has(id) && !this.unacked.has(id) && !this.reacked.has(id)) {
          this.reacked.add(id);
          this.confirm(id, drop.id, file.id, null);
        }
        continue;
      }
      if (this.jobs.has(id) || (outgoing && fileFinished(drop, file))) continue;
      const uri = outgoing ? (uploads.get(file.id) ?? null) : null;
      if (outgoing && uri === null) continue;
      this.jobs.set(id, { id, dropId: drop.id, file, direction: incoming ? "in" : "out", uri, state: "queued", done: 0, attempts: 0, stalled: false, route: null });
    }
    this.pump();
  }

  private end(drop: Drop, incoming: boolean): void {
    const ran = [...this.jobs.values()].some((job) => job.dropId === drop.id);
    this.stopJobs(drop.id);
    this.forget(drop.id);
    if (incoming) {
      const prefix = `${drop.id}/`;
      if (ran && drop.state === "done") this.emit({ _tag: "Received", drop, files: this.received.get().filter((file) => file.id.startsWith(prefix)) });
      return;
    }
    if (this.uploads[drop.id] === undefined) return;
    const { [drop.id]: _ended, ...rest } = this.uploads;
    this.uploads = rest;
    this.save("uploads", rest);
    if (drop.state === "done") {
      this.setSent([{ id: drop.id, label: dropLabel(drop), bytes: drop.bytes, files: drop.files.length, mime: drop.files[0]?.mime ?? null, at: drop.updatedAt }, ...this.sent.get()]);
      this.emit({ _tag: "Sent", drop });
    }
    if (drop.state === "declined") this.emit({ _tag: "Declined", drop });
  }

  private stopJobs(dropId: DropId): void {
    for (const job of this.jobs.values()) {
      if (job.dropId !== dropId) continue;
      if (job.state === "running" || job.state === "starting") void this.engine.cancel(job.id).catch(() => undefined);
      this.jobs.delete(job.id);
    }
    this.pump();
  }

  private forget(dropId: DropId): void {
    this.tickets.delete(dropId);
    const timer = this.refreshTimers.get(dropId);
    if (timer !== undefined) clearTimeout(timer);
    this.refreshTimers.delete(dropId);
  }

  private pump(): void {
    if (this.disposed) return;
    for (const job of nextJobs(this.jobs.values())) void this.start(job);
  }

  private async start(job: Job): Promise<void> {
    job.state = "starting";
    const ticket = await this.ticketFor(job.dropId, job.attempts > 0);
    if (this.jobs.get(job.id) !== job) return;
    if (ticket === null && this.connection.state.get()._tag !== "Ready") {
      job.state = "queued";
      job.stalled = true;
      this.publish(true);
      return;
    }
    if (ticket === null) return this.fail(job, "Your Mac did not let this transfer start");
    job.state = "running";
    const base = { job: job.id, title: fileTitle(job), endpoints: this.endpoints(), ticket: ticket.ticket, dropId: job.dropId, fileId: job.file.id, size: job.file.size };
    try {
      if (job.direction === "in") await this.engine.download({ ...base, name: job.file.name, path: folderOf(job.file.path), mime: job.file.mime });
      else if (job.uri !== null) await this.engine.upload({ ...base, uri: job.uri });
    } catch (error) {
      this.onTransfer({ type: "error", job: job.id, message: messageOf(error), retryable: false });
    }
  }

  private ticketFor(dropId: DropId, fresh: boolean): Promise<DropTicket | null> {
    const known = this.tickets.get(dropId);
    if (!fresh && ticketUsable(known, Date.now())) {
      if (!this.refreshTimers.has(dropId)) this.scheduleRefresh(dropId, known);
      return Promise.resolve(known);
    }
    const pending = this.ticketCalls.get(dropId);
    if (pending !== undefined) return pending;
    const call = this.connection
      .call((client) => client["drop.ticket"]({ id: dropId }))
      .then((result) => {
        this.ticketCalls.delete(dropId);
        if (!result.ok || this.disposed) return null;
        this.tickets.set(dropId, result.value);
        this.scheduleRefresh(dropId, result.value);
        return result.value;
      });
    this.ticketCalls.set(dropId, call);
    return call;
  }

  private scheduleRefresh(dropId: DropId, ticket: DropTicket): void {
    const previous = this.refreshTimers.get(dropId);
    if (previous !== undefined) clearTimeout(previous);
    const timer = setTimeout(() => {
      this.refreshTimers.delete(dropId);
      if (this.unfinished(dropId)) void this.ticketFor(dropId, true);
    }, refreshDelay(ticket.expiresAt, Date.now()));
    this.refreshTimers.set(dropId, timer);
  }

  private unfinished(dropId: DropId): boolean {
    for (const job of this.jobs.values()) if (job.dropId === dropId && job.state !== "done" && job.state !== "failed") return true;
    return false;
  }

  private onTransfer(event: TransferEvent): void {
    const job = this.jobs.get(event.job);
    if (job === undefined) return;
    switch (event.type) {
      case "progress":
        job.done = event.done;
        job.route = event.route;
        job.stalled = false;
        this.publish(false);
        return;
      case "done":
        job.state = "done";
        job.done = job.file.size;
        job.stalled = false;
        if (job.direction === "in") this.landed(job, event.sha256, event.uri);
        this.pump();
        this.publish(true);
        return;
      case "error":
        if (event.retryable) {
          job.stalled = true;
          this.publish(true);
          return;
        }
        if (job.attempts < RETRIES) {
          job.attempts += 1;
          job.state = "queued";
          job.stalled = true;
          this.pump();
          this.publish(true);
          return;
        }
        this.fail(job, event.message);
    }
  }

  private fail(job: Job, reason: string): void {
    job.state = "failed";
    job.stalled = false;
    this.report(reason);
    this.pump();
    this.publish(true);
  }

  private landed(job: Job, sha256: string, uri: string | null): void {
    const expected = this.drops.get().find((drop) => drop.id === job.dropId)?.files.find((file) => file.id === job.file.id)?.sha256 ?? job.file.sha256;
    if (expected !== null && sha256 !== "" && expected !== sha256) return this.fail(job, `${job.file.name} arrived damaged. Send it again.`);
    const saved: SavedFile = { id: job.id, name: job.file.name, path: job.file.path, size: job.file.size, mime: job.file.mime, uri, at: Date.now() };
    this.setReceived([saved, ...this.received.get().filter((file) => file.id !== saved.id)]);
    this.confirm(job.id, job.dropId, job.file.id, sha256 === "" ? null : sha256);
  }

  private confirm(id: string, dropId: DropId, fileId: DropFile["id"], sha256: string | null): void {
    const ack = async (): Promise<boolean> => {
      const result = await this.connection.call((client) => client["drop.received"]({ id: dropId, fileId, sha256 }));
      if (!result.ok) return false;
      this.upsert(result.value);
      this.reconcile(result.value);
      this.publish(true);
      return true;
    };
    this.unacked.set(id, ack);
    void ack().then((ok) => ok && this.unacked.delete(id));
  }

  private flushAcks(): void {
    for (const [id, ack] of this.unacked) void ack().then((ok) => ok && this.unacked.delete(id));
  }

  private emit(finish: DropFinish): void {
    for (const listener of this.finishes) listener(finish);
  }

  private publish(now: boolean): void {
    if (this.disposed) return;
    const wait = now ? 0 : this.lastPublish + PUBLISH_MS - Date.now();
    if (wait > 0) {
      this.publishTimer ??= setTimeout(() => {
        this.publishTimer = null;
        this.publish(true);
      }, wait);
      return;
    }
    if (this.publishTimer !== null) clearTimeout(this.publishTimer);
    this.publishTimer = null;
    this.lastPublish = Date.now();
    this.live.set(this.measure());
  }

  private measure(): ReadonlyMap<DropId, DropLive> {
    const live = new Map<DropId, DropLive>();
    const kept = new Set(this.received.get().map((file) => file.id));
    for (const drop of this.drops.get()) {
      const incoming = isIncoming(drop, this.me);
      if (isEnded(drop) || !(incoming || isOutgoing(drop, this.me))) continue;
      let done = 0;
      let route: DropLive["route"] = null;
      let stalled = false;
      let failed = false;
      for (const file of drop.files) {
        const id = jobIdOf(drop.id, file.id);
        const job = this.jobs.get(id);
        const server = incoming ? 0 : Math.min(file.done, file.size);
        if (job?.state === "done" || (job === undefined && (incoming ? kept.has(id) : fileFinished(drop, file)))) done += file.size;
        else done += Math.max(job?.done ?? 0, server);
        route = job?.route ?? route;
        stalled ||= job?.stalled === true;
        failed ||= job?.state === "failed";
      }
      live.set(drop.id, { done: Math.min(done, drop.bytes), total: drop.bytes, route: route ?? drop.route, stalled, failed });
    }
    return live;
  }
}
