import { channels, colors } from "../theme.ts";
import type { SparkProps } from "./Spark.tsx";

export function Spark({ channel, values, width, height, max, quiet = false }: SparkProps) {
  const top = Math.max(max ?? 0, ...values, 1e-6);
  const step = width / Math.max(values.length - 1, 1);
  const points = values.map((value, index) => `${(index * step).toFixed(1)},${(height - 2 - (Math.max(value, 0) / top) * (height - 4)).toFixed(1)}`).join(" ");
  const color = quiet ? colors.mute : channels[channel].color;
  return (
    <svg width={width} height={height} aria-hidden style={{ display: "block" }}>
      <polyline points={points} fill="none" stroke={color} strokeWidth={1.3} strokeLinejoin="round" />
    </svg>
  );
}
