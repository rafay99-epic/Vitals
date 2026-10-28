import type { GuardRuleKind, HistorySeries, LiveSample, Topic } from "@vitals/contracts";
import { formatCelsius, formatPercent, formatRate, formatRpm, formatWatts } from "@vitals/shared";
import { type Channel, type ChannelState, channels } from "@vitals/ui";

import type { SeriesKey } from "../../state/live.ts";
import { bytes, fanLoad, fixed, type Reading } from "../../state/vitals.ts";

export const LIVE_TOPICS: ReadonlyArray<Topic> = ["cpu", "gpu", "thermal", "fans", "memory", "battery", "power", "network", "disk"];

const GB = 1024 ** 3;

const FULL_BYTES = 10 * GB;

export const diskFull = (sample: LiveSample | null): boolean => {
  const disk = sample?.disk;
  if (disk?.freeBytes === undefined || disk.totalBytes === undefined) return false;
  return disk.freeBytes < Math.min(FULL_BYTES, disk.totalBytes * 0.05);
};

/** SoC rails when IOReport reports them, else the SMC's whole-Mac figure. */
const socWatts = (sample: LiveSample | null): number | null =>
  sample?.power === undefined || sample.power === null ? (sample?.systemWatts ?? null) : sample.power.cpuWatts + sample.power.gpuWatts + sample.power.aneWatts;

export interface PairDef {
  readonly series: SeriesKey;
  readonly history: HistorySeries;
  readonly reading: (sample: LiveSample | null) => Reading;
  readonly label: string;
}

export interface ChannelDef {
  readonly series: SeriesKey;
  readonly topics: ReadonlyArray<Topic>;
  readonly reading: (sample: LiveSample | null) => Reading;
  readonly min: number;
  readonly max: number | null;
  readonly history: HistorySeries;
  readonly historyFormat: (value: number) => string;
  readonly floor: number;
  readonly ceiling: number | undefined;
  readonly elevated: (sample: LiveSample | null) => boolean;
  readonly rules: ReadonlyArray<GuardRuleKind>;
  readonly context: string;
  readonly pair?: PairDef;
}

const rate = (value: number | null | undefined): Reading => {
  const parts = bytes(value);
  return { value: parts.value, unit: parts.unit === "" ? "" : `${parts.unit}/s` };
};

const percent = (value: number | null | undefined): Reading => ({ value: fixed(value), unit: value === null || value === undefined ? "" : "%" });

export const CHANNELS: Record<Channel, ChannelDef> = {
  pulse: {
    series: "cpu",
    topics: ["cpu"],
    reading: (sample) => percent(sample?.cpu?.overall),
    min: 0,
    max: 100,
    history: "cpu",
    historyFormat: (value) => formatPercent(value),
    floor: 0,
    ceiling: 100,
    elevated: (sample) => (sample?.cpu?.overall ?? 0) > 75,
    rules: ["cpuSaturated"],
    context: "load across every core",
  },
  press: {
    series: "memoryUsed",
    topics: ["memory"],
    reading: (sample) => ({ value: fixed(sample?.memory === undefined ? null : sample.memory.usedBytes / GB, 1), unit: sample?.memory === undefined ? "" : `/${String(Math.round(sample.memory.totalBytes / GB))} GB` }),
    min: 0,
    max: null,
    history: "memoryUsedGb",
    historyFormat: (value) => `${value.toFixed(1)} GB`,
    floor: 0,
    ceiling: undefined,
    elevated: (sample) => sample?.memory?.pressure === "warning" || sample?.memory?.pressure === "critical",
    rules: ["memoryPressure", "swapGrowth", "emulatorStack"],
    context: "unified memory in use",
  },
  temp: {
    series: "cpuTemp",
    topics: ["thermal"],
    reading: (sample) => ({ value: sample?.thermal?.cpuC === null || sample?.thermal?.cpuC === undefined ? "--" : `${String(Math.round(sample.thermal.cpuC))}°`, unit: "" }),
    min: 20,
    max: 110,
    history: "cpuTemp",
    historyFormat: (value) => formatCelsius(value),
    floor: 20,
    ceiling: undefined,
    elevated: (sample) => sample?.thermal?.state === "serious" || sample?.thermal?.state === "critical",
    rules: ["thermal"],
    context: "CPU die temperature",
  },
  resp: {
    series: "fan",
    topics: ["fans"],
    reading: (sample) => ({ value: fixed(sample?.fans?.[0]?.rpm), unit: sample?.fans?.[0] === undefined ? "" : "rpm" }),
    min: 0,
    max: null,
    history: "fanRpm",
    historyFormat: (value) => formatRpm(value),
    floor: 0,
    ceiling: undefined,
    elevated: (sample) => fanLoad(sample) > 0.8,
    rules: [],
    context: "fan speed",
  },
  oxy: {
    series: "battery",
    topics: ["battery"],
    reading: (sample) => percent(sample?.battery?.percent),
    min: 0,
    max: 100,
    history: "battery",
    historyFormat: (value) => formatPercent(value),
    floor: 0,
    ceiling: 100,
    elevated: () => false,
    rules: [],
    context: "battery charge",
  },
  eeg: {
    series: "gpu",
    topics: ["gpu", "power", "thermal"],
    reading: (sample) => percent(sample?.gpu?.utilization),
    min: 0,
    max: 100,
    history: "gpu",
    historyFormat: (value) => formatPercent(value),
    floor: 0,
    ceiling: 100,
    elevated: () => false,
    rules: [],
    context: "GPU and Neural Engine",
  },
  drip: {
    series: "socWatts",
    topics: ["power", "battery"],
    reading: (sample) => ({ value: fixed(socWatts(sample), 1), unit: socWatts(sample) === null ? "" : "W" }),
    min: 0,
    max: null,
    history: "socWatts",
    historyFormat: (value) => formatWatts(value),
    floor: 0,
    ceiling: undefined,
    elevated: () => false,
    rules: [],
    context: "package power",
  },
  tele: {
    series: "netIn",
    topics: ["network"],
    reading: (sample) => rate(sample?.network?.inBytesPerSec),
    min: 0,
    max: null,
    history: "networkIn",
    historyFormat: (value) => formatRate(value),
    floor: 0,
    ceiling: undefined,
    elevated: () => false,
    rules: [],
    context: "down and up",
    pair: { series: "netOut", history: "networkOut", reading: (sample) => rate(sample?.network?.outBytesPerSec), label: "up" },
  },
  disk: {
    series: "diskRead",
    topics: ["disk"],
    reading: (sample) => rate(sample?.disk?.readBytesPerSec),
    min: 0,
    max: null,
    history: "diskRead",
    historyFormat: (value) => formatRate(value),
    floor: 0,
    ceiling: undefined,
    elevated: (sample) => diskFull(sample),
    rules: [],
    context: "read and write",
    pair: { series: "diskWrite", history: "diskWrite", reading: (sample) => rate(sample?.disk?.writeBytesPerSec), label: "write" },
  },
};

export const CHART_FULL: ReadonlyArray<Channel> = ["pulse", "press", "temp", "resp", "oxy"];
export const CHART_COMPACT: ReadonlyArray<Channel> = ["eeg", "drip", "tele", "disk"];

export const isChannel = (value: string): value is Channel => Object.hasOwn(channels, value);

export const titleOf = (channel: Channel): string => {
  const tag = channels[channel].tag;
  return `${tag.slice(0, 1)}${tag.slice(1).toLowerCase()}.`;
};

export type LiveState = "waiting" | "normal" | "elevated";

const liveStateOf = (channel: Channel) => (sample: LiveSample | null): LiveState => {
  if (sample === null || CHANNELS[channel].reading(sample).value === "--") return "waiting";
  return CHANNELS[channel].elevated(sample) ? "elevated" : "normal";
};

export const LIVE_STATE: Record<Channel, (sample: LiveSample | null) => LiveState> = {
  pulse: liveStateOf("pulse"),
  press: liveStateOf("press"),
  temp: liveStateOf("temp"),
  resp: liveStateOf("resp"),
  oxy: liveStateOf("oxy"),
  eeg: liveStateOf("eeg"),
  drip: liveStateOf("drip"),
  tele: liveStateOf("tele"),
  disk: liveStateOf("disk"),
};

export const rowState = (live: LiveState, alarmed: boolean, signal: boolean): ChannelState => {
  if (!signal) return "flat";
  if (live === "waiting") return "waiting";
  return alarmed ? "alarm" : live;
};

