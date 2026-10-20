import { useState } from "react";
import { type LayoutChangeEvent, Text, View } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withSpring } from "react-native-reanimated";

const KNOB = 52;

export function SlideToConfirm({
  label,
  onConfirm,
  disabled = false,
}: {
  readonly label: string;
  readonly onConfirm: () => void;
  readonly disabled?: boolean;
}) {
  const [width, setWidth] = useState(0);
  const offset = useSharedValue(0);
  const travel = Math.max(width - KNOB, 1);

  const pan = Gesture.Pan()
    .enabled(!disabled && width > 0)
    .onChange((event) => {
      offset.set(Math.min(Math.max(offset.get() + event.changeX, 0), travel));
    })
    .onEnd(() => {
      const confirmed = offset.get() >= travel * 0.9;
      offset.set(withSpring(0));
      if (confirmed) runOnJS(onConfirm)();
    });

  const knob = useAnimatedStyle(() => ({ transform: [{ translateX: offset.get() }] }));
  const trail = useAnimatedStyle(() => ({ width: offset.get() + KNOB }));

  return (
    <View
      onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)}
      className={`h-[52px] justify-center border border-line ${disabled ? "opacity-40" : ""}`}
      accessibilityRole="adjustable"
      accessibilityLabel={`Slide to ${label}`}
      accessibilityActions={[{ name: "activate" }]}
      onAccessibilityAction={() => onConfirm()}
    >
      <Animated.View className="absolute inset-y-0 left-0 bg-bad/20" style={trail} />
      <Text className="text-center text-[15px] text-dim">{`Slide to ${label}`}</Text>
      <GestureDetector gesture={pan}>
        <Animated.View className="absolute left-0 top-0 h-[50px] w-[52px] items-center justify-center bg-ink" style={knob}>
          <Text className="text-lg text-canvas">{"›"}</Text>
        </Animated.View>
      </GestureDetector>
    </View>
  );
}
