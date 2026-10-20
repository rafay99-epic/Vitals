import type { GuardRuleKind, HistorySeries, LiveSample, Topic } from "@vitals/contracts";
import { formatCelsius, formatPercent, formatRate, formatRpm, formatWatts } from "@vitals/shared";
import { type Channel, type ChannelState, channels } from "@vitals/ui";

import type { SeriesKey } from "../../state/live.ts";
import { bytes, fixed, type Reading } from "../../state/vitals.ts";

export const LIVE_TOPICS: ReadonlyArray<Topic> = ["cpu", "gpu", "thermal", "fans", "memory", "battery", "power", "network"];

const GB = 1024 ** 3;

const fanLoad = (sample: LiveSample | null): number =>
  (sample?.fans ?? []).reduce((load, fan) => Math.max(load, fan.maxRpm > fan.minRpm ? (fan.rpm - fan.minRpm) / (fan.maxRpm - fan.minRpm) : 0), 0);

const socWatts = (sample: LiveSample | null): number | null =>
  sample?.power === undefined || sample.power === null ? null : sample.power.cpuWatts + sample.power.gpuWatts + sample.power.aneWatts;

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
}

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
    topics: ["network", "disk"],
    reading: (sample) => {
      const down = bytes(sample?.network?.inBytesPerSec);
      return { value: down.value, unit: down.unit === "" ? "" : `${down.unit}/s` };
    },
    min: 0,
    max: null,
    history: "networkIn",
    historyFormat: (value) => formatRate(value),
    floor: 0,
    ceiling: undefined,
    elevated: () => false,
    rules: [],
    context: "download rate",
  },
};

export const CHART_FULL: ReadonlyArray<Channel> = ["pulse", "press", "temp", "resp", "oxy"];
export const CHART_COMPACT: ReadonlyArray<Channel> = ["eeg", "drip", "tele"];

export const isChannel = (value: string): value is Channel => value in channels;

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
};

export const rowState = (live: LiveState, alarmed: boolean, signal: boolean): ChannelState => {
  if (!signal) return "flat";
  if (live === "waiting") return "waiting";
  return alarmed ? "alarm" : live;
};

