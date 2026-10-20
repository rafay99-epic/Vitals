import { Canvas, Path, Skia } from "@shopify/react-native-skia";

import { type Channel, channels, colors } from "../theme.ts";

export interface SparkProps {
  readonly channel: Channel;
  readonly values: ReadonlyArray<number>;
  readonly width: number;
  readonly height: number;
  readonly max?: number | undefined;
  readonly quiet?: boolean | undefined;
}

export function Spark({ channel, values, width, height, max, quiet = false }: SparkProps) {
  const top = Math.max(max ?? 0, ...values, 1e-6);
  const step = width / Math.max(values.length - 1, 1);
  const builder = Skia.PathBuilder.Make();
  values.forEach((value, index) => {
    const x = index * step;
    const y = height - 2 - (Math.max(value, 0) / top) * (height - 4);
    if (index === 0) builder.moveTo(x, y);
    else builder.lineTo(x, y);
  });
  return (
    <Canvas style={{ width, height }} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      <Path path={builder.build()} style="stroke" strokeWidth={1.3} color={quiet ? colors.mute : channels[channel].color} strokeJoin="round" />
    </Canvas>
  );
}
