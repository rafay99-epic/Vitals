import { type Connection, Store } from "@vitals/client-runtime";
import type { Alert, AudioState, CommandReceipt, KeepAwakeState, SequencedEvent } from "@vitals/contracts";

const RECEIPTS_KEPT = 50;
const LOG_KEPT = 50;
const CALMED_FOR_MS = 10_000;

export interface AlarmEntry {
  readonly id: string;
  readonly summary: string;
  readonly severity: Alert["severity"];
  readonly raisedAt: number;
  readonly clearedAt: number | null;
}

const entryOf = (alert: Alert): AlarmEntry => ({ id: alert.id, summary: alert.summary, severity: alert.severity, raisedAt: alert.raisedAt, clearedAt: alert.clearedAt });

export class MacEvents {
  readonly keepAwake = new Store<KeepAwakeState | null>(null);
  /** The Mac's volume and mute as the Mac reports them. Null until it does, or on Macs too old to say. */
  readonly audio = new Store<AudioState | null>(null);
  readonly asleepSince = new Store<number | null>(null);
  readonly poweringOff = new Store<number | null>(null);
  readonly alerts = new Store<ReadonlyArray<Alert>>([]);
  readonly receipts = new Store<ReadonlyArray<CommandReceipt>>([]);
  readonly calmed = new Store<boolean>(false);
  readonly log = new Store<ReadonlyArray<AlarmEntry>>([]);
  private calmTimer: ReturnType<typeof setTimeout> | null = null;
  private lastSeq: number | null = null;
  private readonly stops: Array<() => void> = [];

  constructor(connection: Connection) {
    this.stops.push(
      connection.watch(
        (client) => client["system.events"]({ afterSeq: this.lastSeq }),
        (event) => this.apply(event),
      ),
      connection.watch(
        (client) => client["command.log"]({}),
        (receipt) => this.receipt(receipt),
      ),
    );
    // Heartbeats re-emit Ready with the hello from connect time. Apply that snapshot once per
    // connection, or later alerts vanish and cleared ones come back on every beat.
    let applied: object | null = null;
    // The watch reconnects on its own, so it starts once: the first time a connection allows it.
    let watchingAudio = false;
    this.stops.push(
      connection.state.subscribe(() => {
        const state = connection.state.get();
        if (state._tag !== "Ready" || state.hello === applied) return;
        applied = state.hello;
        if (!watchingAudio && state.hello.audio === true) {
          watchingAudio = true;
          this.stops.push(connection.watch((client) => client["system.audio"]({}), (audio) => this.audio.set(audio)));
        }
        this.keepAwake.set(state.hello.keepAwake);
        this.alerts.set(state.hello.alerts);
        for (const alert of state.hello.alerts) this.logRaised(alert);
        if (this.lastSeq === null) this.lastSeq = state.hello.lastEventSeq;
        this.asleepSince.set(null);
        this.poweringOff.set(null);
      }),
    );
  }

  dispose(): void {
    for (const stop of this.stops) stop();
    if (this.calmTimer !== null) clearTimeout(this.calmTimer);
  }

  private markCalmed(finishedAt: number): void {
    const left = CALMED_FOR_MS - (Date.now() - finishedAt);
    if (left <= 0) return;
    if (this.calmTimer !== null) clearTimeout(this.calmTimer);
    this.calmed.set(true);
    this.calmTimer = setTimeout(() => this.calmed.set(false), left);
  }

  private logRaised(alert: Alert): void {
    this.log.update((entries) => (entries.some((entry) => entry.id === alert.id) ? entries : [entryOf(alert), ...entries].slice(0, LOG_KEPT)));
  }

  private logCleared(alert: Alert, at: number): void {
    const clearedAt = alert.clearedAt ?? at;
    const known = this.log.get().some((entry) => entry.id === alert.id);
    this.log.update((entries) =>
      known ? entries.map((entry) => (entry.id === alert.id ? { ...entry, clearedAt } : entry)) : [{ ...entryOf(alert), clearedAt }, ...entries].slice(0, LOG_KEPT),
    );
  }

  receipt(receipt: CommandReceipt): void {
    if (receipt.kind === "CalmDown" && receipt.status === "done") this.markCalmed(receipt.finishedAt ?? receipt.createdAt);
    this.receipts.update((current) => [receipt, ...current.filter((item) => item.id !== receipt.id)].slice(0, RECEIPTS_KEPT));
  }

  private apply({ seq, event }: SequencedEvent): void {
    this.lastSeq = Math.max(this.lastSeq ?? 0, seq);
    switch (event._tag) {
      case "WillSleep":
        this.asleepSince.set(event.at);
        break;
      case "DidWake":
        this.asleepSince.set(null);
        break;
      case "WillPowerOff":
        this.poweringOff.set(event.at);
        break;
      case "KeepAwakeChanged":
        this.keepAwake.set(event.state);
        break;
      case "AlertRaised":
        this.alerts.update((current) => [event.alert, ...current.filter((item) => item.id !== event.alert.id)]);
        this.logRaised(event.alert);
        break;
      case "AlertCleared":
        this.alerts.update((current) => current.filter((item) => item.id !== event.alert.id));
        this.logCleared(event.alert, event.at);
        break;
      case "CommandUpdated":
        this.receipt(event.receipt);
        break;
      case "ThermalChanged":
        break;
    }
  }
}
