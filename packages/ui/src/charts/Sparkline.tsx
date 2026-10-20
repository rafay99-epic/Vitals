import { Canvas, LinearGradient, Path, Skia, vec } from "@shopify/react-native-skia";
import { useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";
import { useDerivedValue } from "react-native-reanimated";

import type { SeriesSource } from "../series.ts";
import { colors } from "../theme.ts";
import { useSeriesValue } from "./useSeriesValue.ts";

export function Sparkline({
  source,
  height = 36,
  color = colors.accent,
  min = 0,
  max,
  capacity = 60,
  fill = true,
}: {
  readonly source: SeriesSource;
  readonly height?: number;
  readonly color?: string;
  readonly min?: number;
  readonly max?: number;
  readonly capacity?: number;
  readonly fill?: boolean;
}) {
  const [width, setWidth] = useState(0);
  const points = useSeriesValue(source);

  const line = useDerivedValue(() => {
    const path = Skia.PathBuilder.Make();
    const values = points.get();
    if (values.length < 2 || width === 0) return path.build();
    let top = max ?? min;
    if (max === undefined) for (const value of values) top = Math.max(top, value);
    const span = Math.max(top - min, 1e-6);
    const step = width / Math.max(capacity - 1, 1);
    const start = width - step * (values.length - 1);
    values.forEach((value, index) => {
      const x = start + step * index;
      const y = height - 2 - ((Math.min(Math.max(value, min), top) - min) / span) * (height - 4);
      if (index === 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    });
    return path.build();
  });

  const area = useDerivedValue(() => {
    const path = line.get();
    const bounds = path.getBounds();
    if (bounds.width === 0) return path;
    return Skia.PathBuilder.MakeFromPath(path)
      .lineTo(bounds.x + bounds.width, height)
      .lineTo(bounds.x, height)
      .close()
      .build();
  });

  return (
    <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)}>
      {width === 0 ? null : (
        <Canvas style={{ width, height }}>
          {fill ? (
            <Path path={area}>
              <LinearGradient start={vec(0, 0)} end={vec(0, height)} colors={[`${color}55`, `${color}00`]} />
            </Path>
          ) : null}
          <Path path={line} style="stroke" strokeWidth={1.5} color={color} strokeJoin="round" />
        </Canvas>
      )}
    </View>
  );
}
