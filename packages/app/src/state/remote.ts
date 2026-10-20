import { type Connection, type ConnectionOptions, type ConnectionState, createConnection, Store } from "@vitals/client-runtime";
import { type Alert, type ActivityLevel, type Command, type CommandReceipt, CommandId, EventId } from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Schema from "effect/Schema";

import { openOutbox } from "../persistence/outbox";
import type { Credentials } from "../persistence/credentialsSchema.ts";
import { MacEvents } from "./events.ts";
import { LiveData } from "./live.ts";

const makeCommandId = Schema.decodeUnknownSync(CommandId);
const makeEventId = Schema.decodeUnknownSync(EventId);
const FLUSH_MS = 10_000;

export const CLIENT_VERSION = "1.0.0";

export interface Toast {
  readonly message: string;
  readonly tone: "ok" | "bad" | "warn";
  readonly at: number;
}

export class Remote {
  readonly connection: Connection;
  readonly live: LiveData;
  readonly events: MacEvents;
  readonly toast = new Store<Toast | null>(null);
  readonly credentials: Credentials;
  private readonly outbox = openOutbox();
  private readonly flushTimer: ReturnType<typeof setInterval>;
  private flushing = false;

  constructor(credentials: Credentials, webSocket: ConnectionOptions["webSocket"], onAlert: (alert: Alert, seq: number) => void) {
    this.credentials = credentials;
    this.connection = createConnection({
      baseUrl: credentials.baseUrl,
      token: credentials.token,
      clientVersion: CLIENT_VERSION,
      webSocket,
      onTransition: (from, to) => this.record(to._tag === "Backoff" ? "warn" : "info", "client.conn.state", transitionData(from, to)),
    });
    this.live = new LiveData(this.connection);
    this.events = new MacEvents(this.connection, onAlert);
    this.flushTimer = setInterval(() => void this.flush(), FLUSH_MS);
  }

  record(level: ActivityLevel, kind: string, data: Record<string, unknown> = {}): void {
    this.outbox.push({ eventId: makeEventId(newId()), at: Date.now(), level, kind, data });
  }

  async run(command: Command): Promise<CommandReceipt | null> {
    this.record("info", "client.ui.command", { kind: command._tag });
    const result = await this.connection.call((client) => client["command.run"]({ commandId: makeCommandId(newId()), command }));
    if (result.ok) {
      this.events.receipt(result.value);
      if (result.value.status === "failed") this.show(result.value.error ?? `${command._tag} failed`, "bad");
      return result.value;
    }
    this.show(result.error.message, "bad");
    this.record("warn", "client.rpc.error", { method: "command.run", tag: result.error._tag });
    return null;
  }

  async cancel(receipt: CommandReceipt): Promise<void> {
    const result = await this.connection.call((client) => client["command.cancel"]({ commandId: receipt.id }));
    if (result.ok) this.events.receipt(result.value);
    else this.show(result.error.message, "bad");
  }

  private toastTimer: ReturnType<typeof setTimeout> | null = null;

  show(message: string, tone: Toast["tone"] = "ok"): void {
    const toast = { message, tone, at: Date.now() };
    this.toast.set(toast);
    if (this.toastTimer !== null) clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => {
      if (this.toast.get() === toast) this.toast.set(null);
    }, 6_000);
  }

  async flush(): Promise<void> {
    if (this.flushing || this.connection.state.get()._tag !== "Ready") return;
    const batch = this.outbox.take(200);
    if (batch.length === 0) return;
    this.flushing = true;
    const result = await this.connection.call((client) => client["activity.ingest"]({ events: batch }));
    if (result.ok) this.outbox.remove(batch.map((event) => event.eventId));
    this.flushing = false;
  }

  discardQueued(): void {
    this.outbox.clear();
  }

  dispose(): void {
    clearInterval(this.flushTimer);
    if (this.toastTimer !== null) clearTimeout(this.toastTimer);
    this.live.dispose();
    this.events.dispose();
    this.connection.dispose();
  }
}

const transitionData = (from: ConnectionState, to: ConnectionState): Record<string, unknown> => ({
  from: from._tag,
  to: to._tag,
  ...(to._tag === "Backoff" ? { attempt: to.attempt, delayMs: to.retryAt - Date.now(), reason: to.reason } : {}),
});
