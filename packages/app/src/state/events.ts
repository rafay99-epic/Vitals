import { type Connection, Store } from "@vitals/client-runtime";
import type { Alert, CommandReceipt, KeepAwakeState, SequencedEvent } from "@vitals/contracts";

const RECEIPTS_KEPT = 50;

export class MacEvents {
  readonly keepAwake = new Store<KeepAwakeState | null>(null);
  readonly asleepSince = new Store<number | null>(null);
  readonly poweringOff = new Store<number | null>(null);
  readonly alerts = new Store<ReadonlyArray<Alert>>([]);
  readonly receipts = new Store<ReadonlyArray<CommandReceipt>>([]);
  private lastSeq: number | null = null;
  private readonly stops: Array<() => void> = [];
  private readonly onAlert: (alert: Alert) => void;

  constructor(connection: Connection, onAlert: (alert: Alert) => void) {
    this.onAlert = onAlert;
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
    this.stops.push(
      connection.state.subscribe(() => {
        const state = connection.state.get();
        if (state._tag !== "Ready") return;
        this.keepAwake.set(state.hello.keepAwake);
        this.alerts.set(state.hello.alerts);
        if (this.lastSeq === null) this.lastSeq = state.hello.lastEventSeq;
        this.asleepSince.set(null);
        this.poweringOff.set(null);
      }),
    );
  }

  dispose(): void {
    for (const stop of this.stops) stop();
  }

  receipt(receipt: CommandReceipt): void {
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
        this.onAlert(event.alert);
        break;
      case "AlertCleared":
        this.alerts.update((current) => current.filter((item) => item.id !== event.alert.id));
        break;
      case "CommandUpdated":
        this.receipt(event.receipt);
        break;
      case "ThermalChanged":
        break;
    }
  }
}
