import { Image } from "expo-image";
import { useState } from "react";
import { type LayoutChangeEvent, StyleSheet, View } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { scheduleOnRN } from "react-native-worklets";

import { curve } from "../ui/index.ts";

const MAX_SCALE = 6;
const DOUBLE_TAP_SCALE = 2.5;
const SETTLE = { duration: 220, easing: curve.out };

/**
 * A picture filling the screen. Pinch to zoom, drag to pan while zoomed, double tap to zoom in or back out.
 * Dragging is off at normal size, so a swipe goes to the screen around it; `onZoom` says when that changes.
 */
export function ImageViewer({ uri, onZoom }: { readonly uri: string; readonly onZoom?: (zoomed: boolean) => void }) {
  const [box, setBox] = useState({ width: 0, height: 0 });
  const [zoomed, setZoomed] = useState(false);
  const zoomTo = (value: boolean) => {
    setZoomed(value);
    onZoom?.(value);
  };
  const scale = useSharedValue(1);
  const startScale = useSharedValue(1);
  const x = useSharedValue(0);
  const y = useSharedValue(0);
  const startX = useSharedValue(0);
  const startY = useSharedValue(0);

  const clampX = (value: number, zoom: number): number => {
    "worklet";
    const limit = (box.width * (zoom - 1)) / 2;
    return Math.min(limit, Math.max(-limit, value));
  };
  const clampY = (value: number, zoom: number): number => {
    "worklet";
    const limit = (box.height * (zoom - 1)) / 2;
    return Math.min(limit, Math.max(-limit, value));
  };

  const pinch = Gesture.Pinch()
    .onStart(() => {
      startScale.set(scale.get());
    })
    .onUpdate((event) => {
      const zoom = Math.min(MAX_SCALE, Math.max(0.8, startScale.get() * event.scale));
      scale.set(zoom);
      x.set(clampX(x.get(), Math.max(1, zoom)));
      y.set(clampY(y.get(), Math.max(1, zoom)));
    })
    .onEnd(() => {
      if (scale.get() < 1) scale.set(withTiming(1, SETTLE));
      scheduleOnRN(zoomTo, scale.get() > 1.01);
    });

  const pan = Gesture.Pan()
    .enabled(zoomed)
    .averageTouches(true)
    .onStart(() => {
      startX.set(x.get());
      startY.set(y.get());
    })
    .onUpdate((event) => {
      const zoom = Math.max(1, scale.get());
      x.set(clampX(startX.get() + event.translationX, zoom));
      y.set(clampY(startY.get() + event.translationY, zoom));
    });

  const doubleTap = Gesture.Tap()
    .numberOfTaps(2)
    .onEnd(() => {
      const wasZoomed = scale.get() > 1.01;
      scale.set(withTiming(wasZoomed ? 1 : DOUBLE_TAP_SCALE, SETTLE));
      if (wasZoomed) {
        x.set(withTiming(0, SETTLE));
        y.set(withTiming(0, SETTLE));
      }
      scheduleOnRN(zoomTo, !wasZoomed);
    });

  const moved = useAnimatedStyle(() => ({ transform: [{ translateX: x.get() }, { translateY: y.get() }, { scale: scale.get() }] }));
  const measure = (event: LayoutChangeEvent) => setBox({ width: event.nativeEvent.layout.width, height: event.nativeEvent.layout.height });

  return (
    <GestureDetector gesture={Gesture.Simultaneous(pinch, pan, doubleTap)}>
      <View style={styles.frame} onLayout={measure} collapsable={false}>
        <Animated.View style={[styles.fill, moved]}>
          <Image source={uri} contentFit="contain" transition={null} style={styles.fill} accessibilityIgnoresInvertColors />
        </Animated.View>
      </View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  frame: { flex: 1, overflow: "hidden" },
});
