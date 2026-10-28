import { useEffect, useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";

import { EMPTY_SERIES } from "../series.ts";
import { type ChannelSpec, type Wave, channels, colors } from "../theme.ts";
import { SvgPen } from "./svgPen.ts";
import type { TraceProps } from "./Trace.tsx";
import { drawWave, peakOf } from "./waves.ts";

const pathOf = (wave: Wave, values: ReadonlyArray<number>, width: number, height: number, min: number, max: number, beats: number): string => {
  const pen = new SvgPen();
  drawWave(pen, wave, { values, width, height, min, max, beats });
  return pen.toString();
};

const useValues = (source: TraceProps["source"]): ReadonlyArray<number> => {
  const [values, setValues] = useState(source.values);
  useEffect(() => source.subscribe(() => setValues(source.values())), [source]);
  return values;
};

export function Trace({ channel, source, pair, height, min = 0, max = null, beats, flat = false }: TraceProps) {
  const spec: ChannelSpec = channels[channel];
  const [width, setWidth] = useState(0);
  const values = useValues(source);
  const pairValues = useValues(pair ?? EMPTY_SERIES);
  const count = beats ?? spec.beats;
  const paired = pair !== undefined && spec.pair !== undefined;
  const top = max ?? peakOf(paired ? [values, pairValues] : [values], count, min);
  const d = flat ? `M0 ${(height * 0.66).toFixed(1)} H${width}` : pathOf(spec.wave, values, width, height, min, top, count);
  const color = flat ? colors.mute : spec.color;
  return (
    <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)} aria-hidden>
      {width === 0 ? null : (
        <svg width={width} height={height} style={{ overflow: "visible", display: "block" }}>
          {flat ? null : <path d={d} fill="none" stroke={color} strokeOpacity={0.16} strokeWidth={5} strokeLinejoin="round" strokeLinecap="round" />}
          <path d={d} fill="none" stroke={color} strokeWidth={1.6} strokeLinejoin="round" strokeLinecap="round" />
          {paired && !flat ? <path d={pathOf("step", pairValues, width, height, min, top, count)} fill="none" stroke={spec.pair} strokeWidth={1.4} strokeLinejoin="round" strokeLinecap="round" /> : null}
          {flat || spec.wave === "bars" ? null : (
            <path d={d} fill="none" stroke={colors.ink} strokeWidth={1.8} pathLength={1} strokeDasharray="0.1 1" strokeDashoffset={-0.9} strokeLinejoin="round" strokeLinecap="round" />
          )}
        </svg>
      )}
    </View>
  );
}
