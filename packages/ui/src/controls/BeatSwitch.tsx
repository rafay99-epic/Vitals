import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { useEffect } from "react";
import { Pressable } from "react-native";
import { useDerivedValue, useSharedValue, withTiming } from "react-native-reanimated";

import { BEAT_OFF, BEAT_ON } from "../nav/glyphPaths.ts";
import { channels, colors } from "../theme.ts";

const empty = Skia.PathBuilder.Make().build();
const OFF = Skia.Path.MakeFromSVGString(BEAT_OFF) ?? empty;
const ON = Skia.Path.MakeFromSVGString(BEAT_ON) ?? empty;

export interface BeatSwitchProps {
  readonly value: boolean;
  readonly onChange: (value: boolean) => void;
  readonly accessibilityLabel: string;
  readonly disabled?: boolean | undefined;
}

export function BeatSwitch({ value, onChange, accessibilityLabel, disabled = false }: BeatSwitchProps) {
  const on = useSharedValue(value ? 1 : 0);
  useEffect(() => {
    on.set(withTiming(value ? 1 : 0, { duration: 200 }));
  }, [value, on]);
  const off = useDerivedValue(() => 1 - on.get());
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
      <Canvas style={{ width: 44, height: 22 }}>
        <Path path={OFF} style="stroke" strokeWidth={1.6} color={colors.mute} opacity={off} strokeCap="round" />
        <Path path={ON} style="stroke" strokeWidth={1.6} color={channels.pulse.color} opacity={on} strokeJoin="round" strokeCap="round" />
      </Canvas>
    </Pressable>
  );
}
