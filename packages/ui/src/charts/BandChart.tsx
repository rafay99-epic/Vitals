import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { useState } from "react";
import { type LayoutChangeEvent, Text, View } from "react-native";

import { colors } from "../theme.ts";

export interface Bucket {
  readonly t: number;
  readonly min: number;
  readonly avg: number;
  readonly max: number;
}

export function BandChart({
  buckets,
  from,
  to,
  height = 140,
  color = colors.accent,
  floor = 0,
  ceiling,
  format,
}: {
  readonly buckets: ReadonlyArray<Bucket>;
  readonly from: number;
  readonly to: number;
  readonly height?: number;
  readonly color?: string;
  readonly floor?: number;
  readonly ceiling?: number;
  readonly format: (value: number) => string;
}) {
  const [width, setWidth] = useState(0);
  const top = ceiling ?? Math.max(floor + 1e-6, ...buckets.map((bucket) => bucket.max));
  const paths = (() => {
    const band = Skia.PathBuilder.Make();
    const line = Skia.PathBuilder.Make();
    if (width === 0 || buckets.length === 0) return { band: band.build(), line: line.build() };
    const x = (t: number) => ((t - from) / Math.max(to - from, 1)) * width;
    const y = (value: number) => height - ((Math.min(Math.max(value, floor), top) - floor) / (top - floor)) * height;
    buckets.forEach((bucket, index) => {
      if (index === 0) band.moveTo(x(bucket.t), y(bucket.max));
      else band.lineTo(x(bucket.t), y(bucket.max));
    });
    for (let index = buckets.length - 1; index >= 0; index -= 1) {
      const bucket = buckets[index];
      if (bucket !== undefined) band.lineTo(x(bucket.t), y(bucket.min));
    }
    band.close();
    buckets.forEach((bucket, index) => {
      if (index === 0) line.moveTo(x(bucket.t), y(bucket.avg));
      else line.lineTo(x(bucket.t), y(bucket.avg));
    });
    return { band: band.build(), line: line.build() };
  })();

  return (
    <View>
      <View className="mb-1 flex-row justify-between">
        <Text className="font-mono text-[10px] text-mute">{format(top)}</Text>
        <Text className="font-mono text-[10px] text-mute">{buckets.length === 0 ? "no data" : `${buckets.length} pts`}</Text>
      </View>
      <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)}>
        {width === 0 ? null : (
          <Canvas style={{ width, height }}>
            <Path path={paths.band} color={color} opacity={0.22} />
            <Path path={paths.line} style="stroke" strokeWidth={1.5} color={color} />
          </Canvas>
        )}
      </View>
      <Text className="mt-1 font-mono text-[10px] text-mute">{format(floor)}</Text>
    </View>
  );
}
