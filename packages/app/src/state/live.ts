import type { Connection } from "@vitals/client-runtime";
import { Store } from "@vitals/client-runtime";
import type { LiveSample, Topic } from "@vitals/contracts";
import { RingBuffer } from "@vitals/shared";
import type { GridSource, SeriesSource } from "@vitals/ui";

const CAPACITY = 60;

export type SeriesKey =
  | "cpu"
  | "pCluster"
  | "eCluster"
  | "gpu"
  | "cpuTemp"
  | "gpuTemp"
  | "fan"
  | "memoryUsed"
  | "memApp"
  | "memWired"
  | "memCompressed"
  | "memCached"
  | "swap"
  | "battery"
  | "batteryWatts"
  | "cpuWatts"
  | "gpuWatts"
  | "socWatts"
  | "netIn"
  | "netOut"
  | "diskRead"
  | "diskWrite";

type Extractor = (sample: LiveSample) => number | null | undefined;

const EXTRACTORS: Record<SeriesKey, Extractor> = {
  cpu: (sample) => sample.cpu?.overall,
  pCluster: (sample) => sample.cpu?.performance,
  eCluster: (sample) => sample.cpu?.efficiency,
  gpu: (sample) => sample.gpu?.utilization,
  cpuTemp: (sample) => sample.thermal?.cpuC,
  gpuTemp: (sample) => sample.thermal?.gpuC,
  fan: (sample) => sample.fans?.[0]?.rpm,
  memoryUsed: (sample) => sample.memory?.usedBytes,
  memApp: (sample) => sample.memory?.appBytes,
  memWired: (sample) => sample.memory?.wiredBytes,
  memCompressed: (sample) => sample.memory?.compressedBytes,
  memCached: (sample) => sample.memory?.cachedBytes,
  swap: (sample) => sample.memory?.swapUsedBytes,
  battery: (sample) => sample.battery?.percent,
  batteryWatts: (sample) => sample.battery?.watts,
  cpuWatts: (sample) => sample.power?.cpuWatts,
  gpuWatts: (sample) => sample.power?.gpuWatts,
  socWatts: (sample) => (sample.power === null || sample.power === undefined ? undefined : sample.power.cpuWatts + sample.power.gpuWatts + sample.power.aneWatts),
  netIn: (sample) => sample.network?.inBytesPerSec,
  netOut: (sample) => sample.network?.outBytesPerSec,
  diskRead: (sample) => sample.disk?.readBytesPerSec,
  diskWrite: (sample) => sample.disk?.writeBytesPerSec,
};

const SERIES_KEYS = Object.keys(EXTRACTORS).filter((key): key is SeriesKey => key in EXTRACTORS);

export class LiveData {
  readonly latest = new Store<LiveSample | null>(null);
  private readonly buffers = new Map<SeriesKey, RingBuffer>(SERIES_KEYS.map((key) => [key, new RingBuffer(CAPACITY)]));
  private readonly sources = new Map<SeriesKey, SeriesSource>();
  private readonly coreBuffers: Array<RingBuffer> = [];
  private readonly listeners = new Set<() => void>();
  private readonly topicCounts = new Map<Topic, number>();
  private stopWatch: (() => void) | null = null;
  private restartTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly connection: Connection;

  readonly cores: GridSource = {
    rows: () => this.coreBuffers.map((buffer) => buffer.toArray()),
    subscribe: (listener) => this.listen(listener),
  };

  constructor(connection: Connection) {
    this.connection = connection;
  }

  series(key: SeriesKey): SeriesSource {
    const existing = this.sources.get(key);
    if (existing !== undefined) return existing;
    const buffer = this.buffers.get(key) ?? new RingBuffer(CAPACITY);
    const source: SeriesSource = {
      values: () => buffer.toArray(),
      subscribe: (listener) => this.listen(listener),
    };
    this.sources.set(key, source);
    return source;
  }

  acquire(topics: ReadonlyArray<Topic>): () => void {
    for (const topic of topics) this.topicCounts.set(topic, (this.topicCounts.get(topic) ?? 0) + 1);
    this.scheduleRestart();
    return () => {
      for (const topic of topics) this.topicCounts.set(topic, Math.max(0, (this.topicCounts.get(topic) ?? 1) - 1));
      this.scheduleRestart();
    };
  }

  dispose(): void {
    this.stopWatch?.();
    if (this.restartTimer !== null) clearTimeout(this.restartTimer);
  }

  private listen(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private scheduleRestart(): void {
    if (this.restartTimer !== null) clearTimeout(this.restartTimer);
    this.restartTimer = setTimeout(() => this.restart(), 60);
  }

  private currentTopics(): Array<Topic> {
    return [...this.topicCounts.entries()].filter(([, count]) => count > 0).map(([topic]) => topic).sort();
  }

  private activeKey = "";

  private restart(): void {
    const topics = this.currentTopics();
    const key = topics.join(",");
    if (key === this.activeKey) return;
    this.activeKey = key;
    this.stopWatch?.();
    this.stopWatch = null;
    if (topics.length === 0) return;
    this.stopWatch = this.connection.watch(
      (client) => client["stats.live"]({ topics }),
      (sample) => this.ingest(sample),
    );
  }

  ingest(sample: LiveSample): void {
    for (const key of SERIES_KEYS) {
      const value = EXTRACTORS[key](sample);
      if (typeof value === "number" && Number.isFinite(value)) this.buffers.get(key)?.push(value);
    }
    const perCore = sample.cpu?.perCore ?? [];
    perCore.forEach((core, index) => {
      const buffer = this.coreBuffers[index] ?? new RingBuffer(CAPACITY);
      this.coreBuffers[index] = buffer;
      buffer.push(core.percent);
    });
    this.latest.update((previous) => (previous === null ? sample : { ...previous, ...sample }));
    for (const listener of this.listeners) listener();
  }
}
