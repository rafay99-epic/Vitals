import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { channels } from "@vitals/ui";
import { useEffect, useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";
import { Easing, useReducedMotion, useSharedValue, withTiming } from "react-native-reanimated";

const HEIGHT = 96;
const DRAW_MS = 1100;

const beat = (width: number) =>
  Skia.PathBuilder.Make()
    .moveTo(0, HEIGHT * 0.62)
    .lineTo(width * 0.38, HEIGHT * 0.62)
    .lineTo(width * 0.44, HEIGHT * 0.8)
    .lineTo(width * 0.5, HEIGHT * 0.12)
    .lineTo(width * 0.56, HEIGHT * 0.62)
    .lineTo(width, HEIGHT * 0.62)
    .build();

export function FirstBeat() {
  const [width, setWidth] = useState(0);
  const still = useReducedMotion();
  const end = useSharedValue(still ? 1 : 0);
  useEffect(() => {
    if (width > 0 && !still) end.set(withTiming(1, { duration: DRAW_MS, easing: Easing.bezier(0.2, 0.8, 0.2, 1) }));
  }, [width, still, end]);
  return (
    <View style={{ height: HEIGHT }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      {width === 0 ? null : (
        <Canvas style={{ width, height: HEIGHT }}>
          <Path path={beat(width)} style="stroke" strokeWidth={2} color={channels.pulse.color} start={0} end={end} strokeJoin="round" strokeCap="round" />
        </Canvas>
      )}
    </View>
  );
}
