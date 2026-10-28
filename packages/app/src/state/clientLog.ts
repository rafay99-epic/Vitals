import { type ActivityLevel, type ClientEvent, EventId } from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Schema from "effect/Schema";

import { openOutbox } from "../persistence/outbox";

const makeEventId = Schema.decodeUnknownSync(EventId);

/** The gateway keeps a line's data only up to 2 KB, so faults are cut to fit. */
const MESSAGE_CHARS = 500;
const STACK_CHARS = 1_200;

type Listener = (event: ClientEvent) => void;

/**
 * The phone's own log: errors, crashes and connection changes. Lines wait on disk until the paired
 * Mac has them (`Remote.flush` sends them to the Mac's Activity log), so a crash or a restart loses
 * nothing. Listeners see each line as it's written; the phone app forwards them to Sentry.
 */
class ClientLog {
  private readonly outbox = openOutbox();
  private readonly listeners = new Set<Listener>();

  record(level: ActivityLevel, kind: string, data: Record<string, unknown> = {}): void {
    const event: ClientEvent = { eventId: makeEventId(newId()), at: Date.now(), level, kind, data };
    this.outbox.push(event);
    for (const listener of this.listeners) listener(event);
  }

  /** An uncaught error. Written before the app dies, so a fatal one still reaches the Mac on the next run. */
  fault(error: unknown, fatal: boolean): void {
    const name = error instanceof Error ? error.name : "Error";
    const message = error instanceof Error ? error.message : String(error);
    const stack = error instanceof Error ? (error.stack ?? "") : "";
    this.record("error", "client.app.fault", { name: name.slice(0, 80), message: message.slice(0, MESSAGE_CHARS), stack: stack.slice(0, STACK_CHARS), fatal });
  }

  take(limit: number): ReadonlyArray<ClientEvent> {
    return this.outbox.take(limit);
  }

  remove(ids: ReadonlyArray<string>): void {
    this.outbox.remove(ids);
  }

  /** Drops every line the Mac hasn't received yet. */
  clear(): void {
    this.outbox.clear();
  }

  listen(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}

export const clientLog = new ClientLog();
