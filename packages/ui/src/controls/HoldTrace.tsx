import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import type { SharedValue } from "react-native-reanimated";

import { beatPoints } from "./holdBeat.ts";

export interface HoldTraceProps {
  readonly width: number;
  readonly height: number;
  readonly color: string;
  readonly progress: SharedValue<number>;
}

const beatPath = (width: number, height: number) => {
  const builder = Skia.PathBuilder.Make();
  beatPoints(width, height).forEach(([x, y], index) => (index === 0 ? builder.moveTo(x, y) : builder.lineTo(x, y)));
  return builder.build();
};

export function HoldTrace({ width, height, color, progress }: HoldTraceProps) {
  return (
    <Canvas style={{ position: "absolute", left: 0, top: 0, width, height }} pointerEvents="none">
      <Path path={beatPath(width, height)} style="stroke" strokeWidth={1.6} color={color} start={0} end={progress} strokeJoin="round" />
    </Canvas>
  );
}
