import { useState } from "react";
import { runOnJS, useAnimatedReaction } from "react-native-reanimated";

import { beatPoints } from "./holdBeat.ts";
import type { HoldTraceProps } from "./HoldTrace.tsx";

export function HoldTrace({ width, height, color, progress }: HoldTraceProps) {
  const [drawn, setDrawn] = useState(0);
  useAnimatedReaction(
    () => progress.get(),
    (next) => runOnJS(setDrawn)(next),
  );
  const d = beatPoints(width, height)
    .map(([x, y], index) => `${index === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`)
    .join(" ");
  return (
    <svg width={width} height={height} aria-hidden style={{ position: "absolute", left: 0, top: 0, pointerEvents: "none" }}>
      <path d={d} fill="none" stroke={color} strokeWidth={1.6} strokeLinejoin="round" pathLength={1} strokeDasharray="1 1" strokeDashoffset={1 - drawn} />
    </svg>
  );
}
