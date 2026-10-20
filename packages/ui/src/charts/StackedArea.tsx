import { Canvas, Path, Skia, type SkPath } from "@shopify/react-native-skia";
import { useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";
import { type DerivedValue, useDerivedValue, useSharedValue } from "react-native-reanimated";
import { useEffect } from "react";

import type { SeriesSource } from "../series.ts";

export interface StackLayer {
  readonly source: SeriesSource;
  readonly color: string;
}

export function StackedArea({
  layers,
  max,
  height = 120,
  capacity = 60,
}: {
  readonly layers: ReadonlyArray<StackLayer>;
  readonly max: number;
  readonly height?: number;
  readonly capacity?: number;
}) {
  const [width, setWidth] = useState(0);
  const stacks = useSharedValue<ReadonlyArray<ReadonlyArray<number>>>(layers.map((layer) => layer.source.values()));

  useEffect(() => {
    const read = () => stacks.set(layers.map((layer) => layer.source.values()));
    read();
    const unsubscribers = layers.map((layer) => layer.source.subscribe(read));
    return () => {
      for (const unsubscribe of unsubscribers) unsubscribe();
    };
  }, [layers, stacks]);

  const paths = useDerivedValue(() => {
    const series = stacks.get();
    const count = series.reduce((longest, values) => Math.max(longest, values.length), 0);
    const step = width / Math.max(capacity - 1, 1);
    const start = width - step * Math.max(count - 1, 0);
    const baseline = Array.from({ length: count }, () => 0);
    return series.map((values) => {
      const path = Skia.PathBuilder.Make();
      if (count < 2 || width === 0) return path.build();
      const offset = count - values.length;
      const tops = baseline.map((base, index) => base + (values[index - offset] ?? 0));
      tops.forEach((top, index) => {
        const x = start + step * index;
        const y = height - (Math.min(top, max) / max) * height;
        if (index === 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      });
      for (let index = count - 1; index >= 0; index -= 1) {
        path.lineTo(start + step * index, height - (Math.min(baseline[index] ?? 0, max) / max) * height);
      }
      path.close();
      tops.forEach((top, index) => {
        baseline[index] = top;
      });
      return path.build();
    });
  });

  return (
    <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)}>
      {width === 0 ? null : (
        <Canvas style={{ width, height }}>
          {layers.map((layer, index) => (
            <LayerPath key={layer.color} paths={paths} index={index} color={layer.color} />
          ))}
        </Canvas>
      )}
    </View>
  );
}

function LayerPath({
  paths,
  index,
  color,
}: {
  readonly paths: DerivedValue<Array<SkPath>>;
  readonly index: number;
  readonly color: string;
}) {
  const path = useDerivedValue(() => paths.get()[index] ?? Skia.PathBuilder.Make().build());
  return <Path path={path} color={color} opacity={0.85} />;
}
