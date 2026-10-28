export const colors = {
  bg: "#000000",
  raise: "#0a0a0a",
  sheet: "#0e0e0e",
  line: "#141414",
  line2: "#1f1f1f",
  line3: "#2c2c2c",
  mute: "#5c5c5c",
  dim: "#8b8b8b",
  ink2: "#c9c9c9",
  ink: "#ffffff",
  alarmHigh: "#ff4d6d",
  alarmMedium: "#ffb45c",
  alarmLow: "#74d4ff",
} as const;

export type Wave = "ecg" | "eeg" | "art" | "wave" | "pleth" | "step" | "bars";

export interface ChannelSpec {
  readonly tag: string;
  readonly label: string;
  readonly color: string;
  readonly wave: Wave;
  readonly beats: number;
  readonly wideBeats: number;
  readonly pair?: string;
}

export const channels = {
  pulse: { tag: "PULSE", label: "CPU", color: "#5cf2a6", wave: "ecg", beats: 6, wideBeats: 28 },
  eeg: { tag: "EEG", label: "GPU", color: "#f2ec6b", wave: "eeg", beats: 10, wideBeats: 30 },
  press: { tag: "PRESS", label: "Memory", color: "#ff6b8b", wave: "art", beats: 6, wideBeats: 26 },
  temp: { tag: "TEMP", label: "Thermal", color: "#ffb45c", wave: "wave", beats: 4, wideBeats: 18 },
  resp: { tag: "RESP", label: "Fans", color: "#74d4ff", wave: "wave", beats: 8, wideBeats: 36 },
  oxy: { tag: "OXY", label: "Battery", color: "#c8a8ff", wave: "pleth", beats: 4, wideBeats: 14 },
  drip: { tag: "DRIP", label: "Power", color: "#6f9bff", wave: "step", beats: 24, wideBeats: 60 },
  tele: { tag: "TELE", label: "Network", color: "#b9c4d0", wave: "bars", beats: 30, wideBeats: 60, pair: "#c8a8ff" },
  disk: { tag: "DISK", label: "Disk", color: "#63e6e2", wave: "bars", beats: 30, wideBeats: 60, pair: "#ffb45c" },
} as const satisfies Record<string, ChannelSpec>;

export type Channel = keyof typeof channels;

export const CHANNEL_ORDER: ReadonlyArray<Channel> = ["pulse", "press", "temp", "resp", "oxy", "eeg", "drip", "tele", "disk"];

export const motion = {
  sample: 400,
  release: 220,
  hold: 1300,
  consent: 2600,
  sheet: 280,
  alarmIn: 260,
  flatline: 600,
  toastIn: 200,
  toastHold: 4000,
} as const;

export const WIDE_MIN_WIDTH = 900;
