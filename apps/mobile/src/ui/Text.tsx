import { StyleSheet, Text as RNText, type TextProps } from "react-native";

import { color, font } from "./tokens.ts";

const variants = StyleSheet.create({
  word: { fontFamily: font.serifItalic, fontSize: 54, lineHeight: 58, color: color.ink },
  title: { fontFamily: font.serifItalic, fontSize: 42, lineHeight: 46, color: color.ink },
  hero: { fontFamily: font.serif, fontSize: 72, lineHeight: 76, color: color.ink },
  value: { fontFamily: font.serif, fontSize: 30, lineHeight: 34, color: color.ink },
  heading: { fontFamily: font.sansSemibold, fontSize: 20, lineHeight: 25, color: color.ink },
  strong: { fontFamily: font.sansSemibold, fontSize: 14, lineHeight: 19, color: color.ink },
  body: { fontFamily: font.sans, fontSize: 14, lineHeight: 20, color: color.ink },
  medium: { fontFamily: font.sansMedium, fontSize: 14, lineHeight: 19, color: color.ink },
  small: { fontFamily: font.sans, fontSize: 12.5, lineHeight: 17, color: color.dim },
  label: { fontFamily: font.sansSemibold, fontSize: 12, lineHeight: 16, color: color.dim },
  tab: { fontFamily: font.sansMedium, fontSize: 10, lineHeight: 13, color: color.mute },
  mono: { fontFamily: font.mono, fontSize: 12, lineHeight: 16, color: color.dim, fontVariant: ["tabular-nums"] },
  monoStrong: { fontFamily: font.monoMedium, fontSize: 13, lineHeight: 17, color: color.ink, fontVariant: ["tabular-nums"] },
  tag: { fontFamily: font.monoMedium, fontSize: 10, lineHeight: 13, letterSpacing: 1, color: color.dim },
});

export type Variant = keyof typeof variants;

export interface TProps extends TextProps {
  readonly v?: Variant;
  readonly color?: string | undefined;
}

/** The one text component. Pick a variant; override colour only when the meaning needs it. */
export function T({ v = "body", color: tint, style, ...rest }: TProps) {
  return <RNText maxFontSizeMultiplier={1.3} {...rest} style={[variants[v], tint === undefined ? null : { color: tint }, style]} />;
}
