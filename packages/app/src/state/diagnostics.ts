import type { Connection, ConnectionState } from "@vitals/client-runtime";
import { RingBuffer } from "@vitals/shared";

import { isDevBuild } from "../lib/variant";

export interface Transition {
  readonly at: number;
  readonly from: string;
  readonly to: string;
  readonly detail: string;
}

export interface Fault {
  readonly at: number;
  readonly message: string;
  readonly fatal: boolean;
}

export interface MethodStats {
  readonly method: string;
  readonly calls: number;
  readonly failures: number;
  readonly lastMs: number;
  readonly p50Ms: number;
  readonly p95Ms: number;
  readonly recent: ReadonlyArray<number>;
}

export interface HeapStats {
  readonly heapBytes: number;
  readonly allocatedBytes: number;
}

const KEPT_TRANSITIONS = 60;
const KEPT_FAULTS = 30;
const KEPT_LATENCIES = 60;
const KEPT_INTERVALS = 120;
const KEPT_FRAMES = 60;

const percentile = (values: ReadonlyArray<number>, fraction: number): number => {
  if (values.length === 0) return Number.NaN;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(fraction * sorted.length))] ?? Number.NaN;
};

const detailOf = (state: ConnectionState): string => {
  switch (state._tag) {
    case "Connecting":
      return `attempt ${String(state.attempt)}`;
    case "Backoff":
      return `${state.reason}, attempt ${String(state.attempt)}`;
    case "Revoked":
      return state.reason;
    case "Incompatible":
      return `server protocol ${String(state.serverProtocol ?? "unknown")}`;
    case "Ready":
    case "Suspended":
    case "Idle":
      return "";
  }
};

const numberField = (source: unknown, key: string): number | null => {
  if (typeof source !== "object" || source === null) return null;
  const value: unknown = Reflect.get(source, key);
  return typeof value === "number" && Number.isFinite(value) ? value : null;
};

const readHeap = (): HeapStats | null => {
  const hermes: unknown = Reflect.get(globalThis, "HermesInternal");
  if (typeof hermes !== "object" || hermes === null) return null;
  const read: unknown = Reflect.get(hermes, "getInstrumentedStats");
  if (typeof read !== "function") return null;
  const stats: unknown = Reflect.apply(read, hermes, []);
  const heapBytes = numberField(stats, "js_heapSize");
  const allocatedBytes = numberField(stats, "js_allocatedBytes");
  return heapBytes === null || allocatedBytes === null ? null : { heapBytes, allocatedBytes };
};

class Method {
  calls = 0;
  failures = 0;
  readonly latencies = new RingBuffer(KEPT_LATENCIES);

  stats(method: string): MethodStats {
    const recent = this.latencies.toArray();
    return {
      method,
      calls: this.calls,
      failures: this.failures,
      lastMs: recent.at(-1) ?? Number.NaN,
      p50Ms: percentile(recent, 0.5),
      p95Ms: percentile(recent, 0.95),
      recent,
    };
  }
}

class Diagnostics {
  readonly enabled = isDevBuild;
  readonly startedAt = Date.now();
  readonly transitions: Array<Transition> = [];
  readonly faults: Array<Fault> = [];
  readonly intervals = new RingBuffer(KEPT_INTERVALS);
  readonly frames = new RingBuffer(KEPT_FRAMES);
  private readonly methods = new Map<string, Method>();
  private lastSampleAt: number | null = null;
  samples = 0;
  reconnects = 0;

  transition(from: ConnectionState, to: ConnectionState): void {
    if (!this.enabled) return;
    if (to._tag === "Backoff") this.reconnects += 1;
    this.transitions.unshift({ at: Date.now(), from: from._tag, to: to._tag, detail: detailOf(to) });
    this.transitions.length = Math.min(this.transitions.length, KEPT_TRANSITIONS);
  }

  rpc(method: string, ms: number, ok: boolean): void {
    if (!this.enabled) return;
    const entry = this.methods.get(method) ?? new Method();
    this.methods.set(method, entry);
    entry.calls += 1;
    if (!ok) entry.failures += 1;
    entry.latencies.push(ms);
  }

  sample(at: number): void {
    if (!this.enabled) return;
    if (this.lastSampleAt !== null) this.intervals.push(at - this.lastSampleAt);
    this.lastSampleAt = at;
    this.samples += 1;
  }

  frame(fps: number): void {
    if (this.enabled) this.frames.push(fps);
  }

  fault(error: unknown, fatal: boolean): void {
    if (!this.enabled) return;
    this.faults.unshift({ at: Date.now(), message: error instanceof Error ? `${error.name}: ${error.message}` : String(error), fatal });
    this.faults.length = Math.min(this.faults.length, KEPT_FAULTS);
  }

  methodStats(): ReadonlyArray<MethodStats> {
    return [...this.methods.entries()].map(([method, entry]) => entry.stats(method)).sort((a, b) => b.calls - a.calls);
  }

  heap(): HeapStats | null {
    return readHeap();
  }

  lastSampleAge(now: number): number | null {
    return this.lastSampleAt === null ? null : now - this.lastSampleAt;
  }

  report(extra: Record<string, unknown>): string {
    return JSON.stringify(
      {
        at: new Date().toISOString(),
        startedAt: new Date(this.startedAt).toISOString(),
        samples: this.samples,
        reconnects: this.reconnects,
        sampleIntervalsMs: this.intervals.toArray(),
        framesPerSecond: this.frames.toArray(),
        heap: this.heap(),
        methods: this.methodStats().map(({ recent: _recent, ...rest }) => rest),
        transitions: this.transitions,
        faults: this.faults,
        ...extra,
      },
      null,
      2,
    );
  }
}

export const diagnostics = new Diagnostics();

const captureFaults = (): void => {
  if (!diagnostics.enabled || typeof ErrorUtils === "undefined") return;
  const previous = ErrorUtils.getGlobalHandler();
  ErrorUtils.setGlobalHandler((error: unknown, fatal?: boolean) => {
    diagnostics.fault(error, fatal === true);
    previous(error, fatal);
  });
};

captureFaults();

export const instrumentConnection = (connection: Connection): Connection => {
  if (!diagnostics.enabled) return connection;
  const call: Connection["call"] = async (run) => {
    let method = "call";
    const started = Date.now();
    const result = await connection.call((client) =>
      run(
        new Proxy(client, {
          get: (target, key, receiver) => {
            if (typeof key === "string") method = key;
            return Reflect.get(target, key, receiver);
          },
        }),
      ),
    );
    diagnostics.rpc(method, Date.now() - started, result.ok);
    return result;
  };
  return { ...connection, call };
};
