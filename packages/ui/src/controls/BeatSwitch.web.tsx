import { Pressable } from "react-native";

import { BEAT_OFF, BEAT_ON } from "../nav/glyphPaths.ts";
import { channels, colors } from "../theme.ts";
import type { BeatSwitchProps } from "./BeatSwitch.tsx";

const FADE = { transition: "opacity 200ms" } as const;

export function BeatSwitch({ value, onChange, accessibilityLabel, disabled = false }: BeatSwitchProps) {
  return (
    <Pressable
      onPress={() => onChange(!value)}
      disabled={disabled}
      hitSlop={10}
      accessibilityRole="switch"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ checked: value, disabled }}
      className={`h-11 w-11 items-center justify-center ${disabled ? "opacity-40" : ""}`}
    >
      <svg width={44} height={22} viewBox="0 0 44 22" aria-hidden style={{ overflow: "visible" }}>
        <path d={BEAT_OFF} fill="none" stroke={colors.mute} strokeWidth={1.6} strokeLinecap="round" style={{ ...FADE, opacity: value ? 0 : 1 }} />
        <path d={BEAT_ON} fill="none" stroke={channels.pulse.color} strokeWidth={1.6} strokeLinejoin="round" strokeLinecap="round" style={{ ...FADE, opacity: value ? 1 : 0 }} />
      </svg>
    </Pressable>
  );
}
