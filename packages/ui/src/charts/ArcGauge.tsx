import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { Text, View } from "react-native";

import { colors } from "../theme.ts";

export function ArcGauge({
  fraction,
  label,
  value,
  size = 120,
}: {
  readonly fraction: number | null;
  readonly label: string;
  readonly value: string;
  readonly size?: number;
}) {
  const stroke = 8;
  const radius = (size - stroke) / 2;
  const oval = Skia.XYWHRect(stroke / 2, stroke / 2, radius * 2, radius * 2);
  const track = Skia.PathBuilder.Make().addArc(oval, 135, 270).build();
  const clamped = fraction === null ? 0 : Math.min(Math.max(fraction, 0), 1);
  const fill = Skia.PathBuilder.Make().addArc(oval, 135, Math.max(270 * clamped, 0.01)).build();
  const tint = clamped >= 0.85 ? colors.bad : clamped >= 0.6 ? colors.warn : colors.accent;
  return (
    <View style={{ width: size, height: size }} accessible accessibilityLabel={`${label} ${value}`}>
      <Canvas style={{ width: size, height: size }}>
        <Path path={track} style="stroke" strokeWidth={stroke} strokeCap="round" color={colors.line} />
        <Path path={fill} style="stroke" strokeWidth={stroke} strokeCap="round" color={tint} />
      </Canvas>
      <View className="absolute inset-0 items-center justify-center">
        <Text className="font-mono text-lg text-ink">{value}</Text>
        <Text className="font-mono text-[10px] uppercase tracking-widest text-mute">{label}</Text>
      </View>
    </View>
  );
}
