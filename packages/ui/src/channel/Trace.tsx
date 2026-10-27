import { Canvas, Path } from "@shopify/react-native-skia";
import { useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";
import { useDerivedValue, useReducedMotion } from "react-native-reanimated";

import { EMPTY_SERIES, type SeriesSource } from "../series.ts";
import { type Channel, type ChannelSpec, channels, colors } from "../theme.ts";
import { useSeriesValue } from "./useSeriesValue.ts";
import { flatPath, peakOf, wavePath } from "./waves.ts";

export interface TraceProps {
  readonly channel: Channel;
  readonly source: SeriesSource;
  readonly pair?: SeriesSource | undefined;
  readonly height: number;
  readonly min?: number | undefined;
  readonly max?: number | null | undefined;
  readonly beats?: number | undefined;
  readonly flat?: boolean | undefined;
}

export function Trace({ channel, source, pair, height, min = 0, max = null, beats, flat = false }: TraceProps) {
  const spec: ChannelSpec = channels[channel];
  const [width, setWidth] = useState(0);
  const points = useSeriesValue(source);
  const pairPoints = useSeriesValue(pair ?? EMPTY_SERIES);
  const still = useReducedMotion();
  const count = beats ?? spec.beats;
  const paired = pair !== undefined && spec.pair !== undefined;

  const top = useDerivedValue(() => max ?? peakOf(paired ? [points.get(), pairPoints.get()] : [points.get()], count, min));
  const path = useDerivedValue(() =>
    flat ? flatPath(width, height) : wavePath(spec.wave, { values: points.get(), width, height, min, max: top.get(), beats: count }),
  );
  const pairPath = useDerivedValue(() =>
    flat || !paired ? flatPath(0, 0) : wavePath("step", { values: pairPoints.get(), width, height, min, max: top.get(), beats: count }),
  );

  const color = flat ? colors.mute : spec.color;
  const head = !flat && !still && spec.wave !== "bars";

  return (
    <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      {width === 0 ? null : (
        <Canvas style={{ width, height }}>
          {flat ? null : <Path path={path} style="stroke" strokeWidth={5} color={color} opacity={0.16} strokeJoin="round" strokeCap="round" />}
          <Path path={path} style="stroke" strokeWidth={1.6} color={color} strokeJoin="round" strokeCap="round" />
          {paired && !flat ? <Path path={pairPath} style="stroke" strokeWidth={1.4} color={spec.pair} strokeJoin="round" strokeCap="round" /> : null}
          {head ? <Path path={path} style="stroke" strokeWidth={1.8} color={colors.ink} start={0.9} end={1} strokeJoin="round" strokeCap="round" /> : null}
        </Canvas>
      )}
    </View>
  );
}
