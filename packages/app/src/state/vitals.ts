import type { ConnectionState } from "@vitals/client-runtime";
import type { Alert, GuardRuleKind, LiveSample } from "@vitals/contracts";
import type { LinkTone, Tone } from "@vitals/ui";

export interface Word {
  readonly word: string;
  readonly tone: Tone;
}

const WORDS = {
  resting: { word: "Resting.", tone: "ink" },
  elevated: { word: "Elevated.", tone: "temp" },
  racing: { word: "Racing.", tone: "press" },
  breathing: { word: "Breathing hard.", tone: "resp" },
  pressure: { word: "Pressure rising.", tone: "press" },
  fever: { word: "Fever.", tone: "temp" },
  noSignal: { word: "No signal.", tone: "mute" },
  asleep: { word: "Asleep.", tone: "dim" },
  calmed: { word: "Calmed.", tone: "pulse" },
} as const satisfies Record<string, Word>;

const ALARM_WORD: Record<GuardRuleKind, string> = {
  memoryPressure: "Pressure high.",
  swapGrowth: "Swap climbing.",
  cpuSaturated: "Racing.",
  agentOverload: "Agents crowding.",
  emulatorStack: "Emulators fighting.",
  thermal: "Fever.",
};

const FAN_HARD = 0.8;

export const fanLoad = (sample: LiveSample | null): number =>
  (sample?.fans ?? []).reduce((load, fan) => Math.max(load, fan.maxRpm > fan.minRpm ? (fan.rpm - fan.minRpm) / (fan.maxRpm - fan.minRpm) : 0), 0);

const HOT = new Set(["serious", "critical"]);
const TIGHT = new Set(["warning", "critical"]);

export const sampleWord = (sample: LiveSample | null): Word => {
  if (sample === null) return WORDS.resting;
  if (HOT.has(sample.thermal?.state ?? "")) return WORDS.fever;
  if (TIGHT.has(sample.memory?.pressure ?? "")) return WORDS.pressure;
  if (fanLoad(sample) > FAN_HARD) return WORDS.breathing;
  const cpu = sample.cpu?.overall ?? 0;
  if (cpu > 75) return WORDS.racing;
  return cpu >= 45 ? WORDS.elevated : WORDS.resting;
};

export interface WordInput {
  readonly vitals: Word;
  readonly alerts: ReadonlyArray<Alert>;
  readonly signal: boolean;
  readonly asleep: boolean;
  readonly calmed: boolean;
}

export const stateWord = ({ vitals, alerts, signal, asleep, calmed }: WordInput): Word => {
  const alert = alerts[0];
  if (alert !== undefined) return { word: ALARM_WORD[alert.rule], tone: alert.severity === "critical" ? "alarmHigh" : "press" };
  if (!signal) return WORDS.noSignal;
  if (asleep) return WORDS.asleep;
  if (calmed) return WORDS.calmed;
  return vitals;
};

export interface Link {
  readonly label: string;
  readonly tone: LinkTone;
}

export const linkOf = (state: ConnectionState): Link => {
  switch (state._tag) {
    case "Ready":
      return state.hello.mac === null ? { label: "no signal", tone: "off" } : { label: "live", tone: "live" };
    case "Connecting":
      return { label: "connecting", tone: "quiet" };
    case "Backoff":
      return { label: "reconnecting", tone: "warn" };
    case "Suspended":
      return { label: "paused", tone: "quiet" };
    case "Revoked":
      return { label: "removed", tone: "off" };
    case "Incompatible":
      return { label: "out of step", tone: "off" };
    case "Idle":
      return { label: "starting", tone: "quiet" };
  }
};

export const hasSignal = (state: ConnectionState): boolean => state._tag === "Ready" && state.hello.mac !== null;

const BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"] as const;

export interface Reading {
  readonly value: string;
  readonly unit: string;
}

export const bytes = (value: number | null | undefined, digits = 1): Reading => {
  if (value === null || value === undefined || !Number.isFinite(value) || value < 0) return { value: "--", unit: "" };
  if (value === 0) return { value: "0", unit: "B" };
  const exponent = Math.max(0, Math.min(Math.floor(Math.log(value) / Math.log(1024)), BYTE_UNITS.length - 1));
  return { value: (value / 1024 ** exponent).toFixed(exponent === 0 ? 0 : digits), unit: BYTE_UNITS[exponent] ?? "B" };
};

export const fixed = (value: number | null | undefined, digits = 0): string =>
  value === null || value === undefined || !Number.isFinite(value) ? "--" : value.toFixed(digits);
