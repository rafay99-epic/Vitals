import type { ReactNode } from "react";
import { Text, type TextProps } from "react-native";

import type { Channel } from "./theme.ts";

export type Tone = "ink" | "ink2" | "dim" | "mute" | "alarmHigh" | "alarmMedium" | "alarmLow" | "black" | Channel;

const TONE: Record<Tone, string> = {
  ink: "text-ink",
  ink2: "text-ink2",
  dim: "text-dim",
  mute: "text-mute",
  alarmHigh: "text-alarm-high",
  alarmMedium: "text-alarm-medium",
  alarmLow: "text-alarm-low",
  black: "text-bg",
  pulse: "text-pulse",
  eeg: "text-eeg",
  press: "text-press",
  temp: "text-temp",
  resp: "text-resp",
  oxy: "text-oxy",
  drip: "text-drip",
  tele: "text-tele",
};

export type SerifSize = "hero" | "xl2" | "state" | "l" | "m" | "s";

const SERIF: Record<SerifSize, string> = {
  hero: "text-hero",
  xl2: "text-xl2",
  state: "text-state",
  l: "text-l",
  m: "text-m",
  s: "text-s",
};

type Base = Omit<TextProps, "children"> & {
  readonly tone?: Tone | undefined;
  readonly className?: string | undefined;
  readonly children?: ReactNode;
};

const TABULAR = { fontVariant: ["tabular-nums"] } as const;

export function Serif({ size = "m", italic = false, tone = "ink", className = "", style, ...rest }: Base & { readonly size?: SerifSize; readonly italic?: boolean }) {
  return (
    <Text
      maxFontSizeMultiplier={1.3}
      className={`${italic ? "font-display-italic" : "font-display"} ${SERIF[size]} ${TONE[tone]} ${className}`}
      style={[TABULAR, style]}
      {...rest}
    />
  );
}

export type SansSize = "body" | "small";

const SANS: Record<SansSize, string> = { body: "text-body", small: "text-small" };

type SansWeight = "regular" | "medium" | "semibold";

const SANS_WEIGHT: Record<SansWeight, string> = { regular: "font-text", medium: "font-text-medium", semibold: "font-text-semibold" };

export function Sans({ size = "body", weight = "regular", tone = "ink", className = "", ...rest }: Base & { readonly size?: SansSize; readonly weight?: SansWeight }) {
  return <Text maxFontSizeMultiplier={1.5} className={`${SANS_WEIGHT[weight]} ${SANS[size]} ${TONE[tone]} ${className}`} {...rest} />;
}

export function Mono({ tone = "dim", className = "", style, ...rest }: Base) {
  return <Text maxFontSizeMultiplier={1.5} className={`font-code text-meta ${TONE[tone]} ${className}`} style={[TABULAR, style]} {...rest} />;
}

export function Tag({ tone = "ink2", className = "", ...rest }: Base) {
  return <Text maxFontSizeMultiplier={1.5} className={`font-code-medium text-tag uppercase tracking-widest ${TONE[tone]} ${className}`} {...rest} />;
}
