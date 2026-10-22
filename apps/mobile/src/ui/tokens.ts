import { Easing } from "react-native-reanimated";

/** Mobile design tokens. True black, white text, yellow accent, orange and red for trouble. */
export const color = {
  bg: "#000000",
  s1: "#0b0b0b",
  s2: "#131313",
  s3: "#1b1b1b",
  line: "#1c1c1c",
  line2: "#2a2a2a",
  mute: "#6b6b6b",
  dim: "#9c9c9c",
  ink2: "#d4d4d4",
  ink: "#ffffff",
  yellow: "#f2ec6b",
  orange: "#ffb45c",
  red: "#ff4d6d",
  green: "#5cf2a6",
  blue: "#74d4ff",
  pink: "#ff6b8b",
  violet: "#c8a8ff",
  drip: "#6f9bff",
  tele: "#b9c4d0",
  scrim: "rgba(0,0,0,0.7)",
} as const;

export type Color = keyof typeof color;

export const font = {
  serif: "InstrumentSerif-Regular",
  serifItalic: "InstrumentSerif-Italic",
  sans: "Geist-Regular",
  sansMedium: "Geist-Medium",
  sansSemibold: "Geist-SemiBold",
  mono: "GeistMono-Regular",
  monoMedium: "GeistMono-Medium",
} as const;

/** Easing curves shared by every animation, so the whole app moves the same way. */
export const curve = {
  tray: Easing.bezier(0.32, 0.72, 0, 1),
  out: Easing.bezier(0.23, 1, 0.32, 1),
} as const;

/** Durations in ms. Only transform and opacity animate; nothing loops. */
export const motion = {
  sheetIn: 300,
  sheetOut: 200,
  dock: 320,
  pressIn: 100,
  pressOut: 160,
  pressScale: 0.97,
  hold: 1300,
  toastIn: 240,
  toastOut: 160,
  toastHold: 4000,
  toggle: 260,
  segment: 300,
} as const;

export const space = { gutter: 20, edge: 16 } as const;

/** Height the floating dock takes from the bottom edge, before the safe-area inset. */
export const DOCK_HEIGHT = 62;
export const DOCK_BOTTOM = 12;
