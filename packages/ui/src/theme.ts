export const colors = {
  canvas: "#000000",
  ink: "#ffffff",
  dim: "#a1a1a1",
  mute: "#6b6b6b",
  line: "#1c1c1c",
  ok: "#5ee38a",
  warn: "#ffcc4d",
  bad: "#ff6b6b",
  accent: "#7cc4ff",
  violet: "#b69cff",
} as const;

export type ColorName = keyof typeof colors;

export const loadColor = (fraction: number): string =>
  fraction >= 0.85 ? colors.bad : fraction >= 0.6 ? colors.warn : fraction >= 0.25 ? colors.accent : colors.mute;
