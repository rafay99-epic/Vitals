import { useEffect, useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";

import { type Channel, channels, colors } from "../theme.ts";
import { SvgPen } from "./svgPen.ts";
import type { TraceProps } from "./Trace.tsx";
import { drawWave } from "./waves.ts";

const pathOf = (channel: Channel, values: ReadonlyArray<number>, width: number, height: number, min: number, max: number | null, beats: number): string => {
  const pen = new SvgPen();
  drawWave(pen, channels[channel].wave, { values, width, height, min, max, beats });
  return pen.toString();
};

export function Trace({ channel, source, height, min = 0, max = null, beats, flat = false }: TraceProps) {
  const spec = channels[channel];
  const [width, setWidth] = useState(0);
  const [values, setValues] = useState(source.values);
  useEffect(() => source.subscribe(() => setValues(source.values())), [source]);
  const d = flat ? `M0 ${(height * 0.66).toFixed(1)} H${width}` : pathOf(channel, values, width, height, min, max, beats ?? spec.beats);
  const color = flat ? colors.mute : spec.color;
  return (
    <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)} aria-hidden>
      {width === 0 ? null : (
        <svg width={width} height={height} style={{ overflow: "visible", display: "block" }}>
          {flat ? null : <path d={d} fill="none" stroke={color} strokeOpacity={0.16} strokeWidth={5} strokeLinejoin="round" strokeLinecap="round" />}
          <path d={d} fill="none" stroke={color} strokeWidth={1.6} strokeLinejoin="round" strokeLinecap="round" />
          {flat || spec.wave === "bars" ? null : (
            <path d={d} fill="none" stroke={colors.ink} strokeWidth={1.8} pathLength={1} strokeDasharray="0.1 1" strokeDashoffset={-0.9} strokeLinejoin="round" strokeLinecap="round" />
          )}
        </svg>
      )}
    </View>
  );
}
