import { Canvas, Path } from "@shopify/react-native-skia";
import { useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";
import { useDerivedValue, useReducedMotion } from "react-native-reanimated";

import type { SeriesSource } from "../series.ts";
import { type Channel, channels, colors } from "../theme.ts";
import { useSeriesValue } from "./useSeriesValue.ts";
import { flatPath, wavePath } from "./waves.ts";

export interface TraceProps {
  readonly channel: Channel;
  readonly source: SeriesSource;
  readonly height: number;
  readonly min?: number | undefined;
  readonly max?: number | null | undefined;
  readonly beats?: number | undefined;
  readonly flat?: boolean | undefined;
}

export function Trace({ channel, source, height, min = 0, max = null, beats, flat = false }: TraceProps) {
  const spec = channels[channel];
  const [width, setWidth] = useState(0);
  const points = useSeriesValue(source);
  const still = useReducedMotion();
  const count = beats ?? spec.beats;

  const path = useDerivedValue(() =>
    flat ? flatPath(width, height) : wavePath(spec.wave, { values: points.get(), width, height, min, max, beats: count }),
  );

  const color = flat ? colors.mute : spec.color;
  const head = !flat && !still && spec.wave !== "bars";

  return (
    <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      {width === 0 ? null : (
        <Canvas style={{ width, height }}>
          {flat ? null : <Path path={path} style="stroke" strokeWidth={5} color={color} opacity={0.16} strokeJoin="round" strokeCap="round" />}
          <Path path={path} style="stroke" strokeWidth={1.6} color={color} strokeJoin="round" strokeCap="round" />
          {head ? <Path path={path} style="stroke" strokeWidth={1.8} color={colors.ink} start={0.9} end={1} strokeJoin="round" strokeCap="round" /> : null}
        </Canvas>
      )}
    </View>
  );
}
