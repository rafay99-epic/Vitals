import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";

import { type Channel, channels, colors } from "../theme.ts";
import { Mono } from "../typography.tsx";

export interface Bucket {
  readonly t: number;
  readonly min: number;
  readonly avg: number;
  readonly max: number;
}

export interface HistoryChartProps {
  readonly channel: Channel;
  readonly buckets: ReadonlyArray<Bucket>;
  readonly from: number;
  readonly to: number;
  readonly labels: ReadonlyArray<string>;
  readonly format: (value: number) => string;
  readonly floor?: number | undefined;
  readonly ceiling?: number | undefined;
  readonly height?: number | undefined;
}

const GRID = [0.25, 0.5, 0.75];

const MARKER = 12;

const markerSpan = (top: number): readonly [number, number] => (top >= MARKER + 4 ? [top - 4, top - 4 - MARKER] : [top + 4, top + 4 + MARKER]);

const geometry = (buckets: ReadonlyArray<Bucket>, from: number, to: number, width: number, height: number, floor: number, top: number) => {
  const x = (t: number) => ((t - from) / Math.max(to - from, 1)) * width;
  const y = (value: number) => height - ((Math.min(Math.max(value, floor), top) - floor) / Math.max(top - floor, 1e-6)) * height;
  const band = Skia.PathBuilder.Make();
  const line = Skia.PathBuilder.Make();
  const grid = Skia.PathBuilder.Make();
  for (const level of GRID) grid.moveTo(0, height * level).lineTo(width, height * level);
  buckets.forEach((bucket, index) => {
    if (index === 0) {
      band.moveTo(x(bucket.t), y(bucket.max));
      line.moveTo(x(bucket.t), y(bucket.avg));
      return;
    }
    band.lineTo(x(bucket.t), y(bucket.max));
    line.lineTo(x(bucket.t), y(bucket.avg));
  });
  buckets.toReversed().forEach((bucket) => band.lineTo(x(bucket.t), y(bucket.min)));
  band.close();
  const peak = buckets.reduce<Bucket | null>((best, bucket) => (best === null || bucket.max > best.max ? bucket : best), null);
  const marker = Skia.PathBuilder.Make();
  if (peak !== null) {
    const [from, to] = markerSpan(y(peak.max));
    marker.moveTo(x(peak.t), from).lineTo(x(peak.t), to);
  }
  return { band: band.build(), line: line.build(), grid: grid.build(), marker: marker.build(), peak, peakX: peak === null ? 0 : x(peak.t) };
};

export function HistoryChart({ channel, buckets, from, to, labels, format, floor = 0, ceiling, height = 120 }: HistoryChartProps) {
  const [width, setWidth] = useState(0);
  const color = channels[channel].color;
  const top = ceiling ?? Math.max(floor + 1e-6, ...buckets.map((bucket) => bucket.max));
  const shapes = geometry(buckets, from, to, width, height, floor, top);
  return (
    <View>
      <View className="mb-1 h-4 flex-row">
        {shapes.peak === null ? null : (
          <View className="absolute" style={{ left: Math.min(Math.max(shapes.peakX - 60, 0), Math.max(width - 120, 0)), width: 120 }}>
            <Mono tone="ink" className="text-center text-[10px]">{`peak ${format(shapes.peak.max)}`}</Mono>
          </View>
        )}
      </View>
      <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)}>
        {width === 0 ? null : (
          <Canvas style={{ width, height }}>
            <Path path={shapes.grid} style="stroke" strokeWidth={1} color={colors.line} />
            <Path path={shapes.band} color={color} opacity={0.09} />
            <Path path={shapes.line} style="stroke" strokeWidth={1.5} color={color} strokeJoin="round" />
            <Path path={shapes.marker} style="stroke" strokeWidth={1} color={colors.ink} />
          </Canvas>
        )}
      </View>
      <View className="mt-1.5 flex-row justify-between">
        {labels.map((label) => (
          <Mono key={label} className="text-[10px]">
            {label}
          </Mono>
        ))}
      </View>
    </View>
  );
}
