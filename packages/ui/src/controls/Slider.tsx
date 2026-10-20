import { useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { runOnJS, useAnimatedStyle, useSharedValue } from "react-native-reanimated";

import { Mono } from "../typography.tsx";

export interface SliderProps {
  readonly value: number;
  readonly onCommit: (value: number) => void;
  readonly format: (value: number) => string;
  readonly accessibilityLabel: string;
  readonly disabled?: boolean | undefined;
}

const STEP = 0.05;

const clamp = (value: number): number => {
  "worklet";
  return Math.min(1, Math.max(0, value));
};

export function Slider({ value, onCommit, format, accessibilityLabel, disabled = false }: SliderProps) {
  const [width, setWidth] = useState(0);
  const [shown, setShown] = useState(value);
  const position = useSharedValue(value);
  const track = useSharedValue(0);

  const move = (x: number) => {
    "worklet";
    const next = clamp(x / Math.max(track.get(), 1));
    position.set(next);
    runOnJS(setShown)(Math.round(next / STEP) * STEP);
  };

  const finish = () => {
    "worklet";
    runOnJS(onCommit)(Math.round(position.get() / STEP) * STEP);
  };

  const pan = Gesture.Pan()
    .enabled(!disabled)
    .onBegin((event) => move(event.x))
    .onUpdate((event) => move(event.x))
    .onEnd(finish);
  const tap = Gesture.Tap()
    .enabled(!disabled)
    .onEnd((event) => {
      move(event.x);
      finish();
    });

  const thumb = useAnimatedStyle(() => ({ transform: [{ translateX: position.get() * track.get() - 1 }] }));
  const fill = useAnimatedStyle(() => ({ width: position.get() * track.get() }));

  const nudge = (delta: number) => {
    const next = clamp(position.get() + delta);
    position.set(next);
    setShown(next);
    onCommit(next);
  };

  return (
    <View className={`flex-1 flex-row items-center gap-4 ${disabled ? "opacity-40" : ""}`}>
      <GestureDetector gesture={Gesture.Race(pan, tap)}>
        <View
          className="h-11 flex-1 justify-center"
          onLayout={(event: LayoutChangeEvent) => {
            setWidth(event.nativeEvent.layout.width);
            track.set(event.nativeEvent.layout.width);
          }}
          accessible
          accessibilityRole="adjustable"
          accessibilityLabel={accessibilityLabel}
          accessibilityValue={{ min: 0, max: 100, now: Math.round(shown * 100), text: format(shown) }}
          accessibilityActions={[{ name: "increment" }, { name: "decrement" }]}
          onAccessibilityAction={(event) => nudge(event.nativeEvent.actionName === "increment" ? 0.1 : -0.1)}
        >
          <View className="h-px bg-line3" />
          {width === 0 ? null : (
            <>
              <Animated.View className="absolute h-px bg-ink2" style={fill} />
              <Animated.View className="absolute h-[26px] w-0.5 bg-ink" style={thumb} />
            </>
          )}
        </View>
      </GestureDetector>
      <Mono tone="ink" className="w-10 text-right">
        {format(shown)}
      </Mono>
    </View>
  );
}
