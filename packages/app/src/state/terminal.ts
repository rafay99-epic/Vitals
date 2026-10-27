import type { Connection } from "@vitals/client-runtime";
import { Store } from "@vitals/client-runtime";
import type { TerminalEvent, TerminalId, TerminalInfo, TerminalSize } from "@vitals/contracts";

const INPUT_MS = 8;

export interface TerminalSink {
  readonly reset: () => void;
  readonly write: (data: string) => void;
}

export interface TerminalStatus {
  readonly exited: boolean;
  readonly exitCode: number | null;
  readonly attached: boolean;
}

export class TerminalSession {
  readonly status = new Store<TerminalStatus>({ exited: false, exitCode: null, attached: false });
  private readonly connection: Connection;
  private readonly id: TerminalId;
  private size: TerminalSize;
  private sink: TerminalSink | null = null;
  private stop: (() => void) | null = null;
  private inputTimer: ReturnType<typeof setTimeout> | null = null;
  private pendingInput = "";

  constructor(connection: Connection, id: TerminalId, size: TerminalSize) {
    this.connection = connection;
    this.id = id;
    this.size = size;
  }

  attach(sink: TerminalSink): void {
    this.sink = sink;
    if (this.stop !== null) return;
    this.stop = this.connection.watch(
      (client) => client["terminal.attach"]({ id: this.id, cols: this.size.cols, rows: this.size.rows }),
      (event) => this.apply(event),
    );
  }

  detach(): void {
    this.stop?.();
    this.stop = null;
    this.sink = null;
    this.status.update((status) => ({ ...status, attached: false }));
  }

  input(data: string): void {
    if (this.status.get().exited || data.length === 0) return;
    this.pendingInput += data;
    this.inputTimer ??= setTimeout(() => this.flushInput(), INPUT_MS);
  }

  resize(size: TerminalSize): void {
    if (size.cols === this.size.cols && size.rows === this.size.rows) return;
    this.size = size;
    void this.connection.call((client) => client["terminal.resize"]({ id: this.id, cols: size.cols, rows: size.rows }));
  }

  dispose(): void {
    this.detach();
    if (this.inputTimer !== null) clearTimeout(this.inputTimer);
  }

  private flushInput(): void {
    this.inputTimer = null;
    const data = this.pendingInput;
    this.pendingInput = "";
    if (data.length > 0) void this.connection.call((client) => client["terminal.write"]({ id: this.id, data }));
  }

  private apply(event: TerminalEvent): void {
    switch (event._tag) {
      case "Snapshot":
        this.status.set({ exited: !event.info.running, exitCode: event.info.exitCode, attached: true });
        this.sink?.reset();
        this.sink?.write(event.history);
        return;
      case "Output":
        this.sink?.write(event.data);
        return;
      case "Exited":
        this.status.update((status) => ({ ...status, exited: true, exitCode: event.code }));
        return;
    }
  }
}

export class MacTerminals {
  readonly sessions = new Store<ReadonlyArray<TerminalInfo>>([]);
  private readonly connection: Connection;
  private readonly open = new Map<string, TerminalSession>();

  constructor(connection: Connection) {
    this.connection = connection;
  }

  async refresh(): Promise<void> {
    const result = await this.connection.call((client) => client["terminal.list"]({}));
    if (result.ok) this.sessions.set(result.value.sessions);
  }

  async start(size: TerminalSize): Promise<TerminalInfo | string> {
    const result = await this.connection.call((client) => client["terminal.open"](size));
    if (!result.ok) return result.error.message;
    this.sessions.update((sessions) => [...sessions, result.value]);
    return result.value;
  }

  session(id: TerminalId, size: TerminalSize): TerminalSession {
    const existing = this.open.get(id);
    if (existing !== undefined) {
      existing.resize(size);
      return existing;
    }
    const created = new TerminalSession(this.connection, id, size);
    this.open.set(id, created);
    return created;
  }

  async end(id: TerminalId): Promise<void> {
    await this.connection.call((client) => client["terminal.close"]({ id }));
    this.open.get(id)?.dispose();
    this.open.delete(id);
    this.sessions.update((sessions) => sessions.filter((session) => session.id !== id));
  }

  dispose(): void {
    for (const session of this.open.values()) session.dispose();
    this.open.clear();
  }
}
