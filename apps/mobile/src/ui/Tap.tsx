import type { ReactNode } from "react";
import { type GestureResponderEvent, Pressable, type PressableProps, type StyleProp, type ViewStyle } from "react-native";
import Animated, { useAnimatedStyle, useReducedMotion, useSharedValue, withTiming } from "react-native-reanimated";

import { curve, motion } from "./tokens.ts";

export interface TapProps extends Omit<PressableProps, "style" | "children"> {
  readonly style?: StyleProp<ViewStyle>;
  readonly children?: ReactNode;
  readonly scale?: number;
  /** Layout for the touch target itself (flex, width). Visual styles go in `style`. */
  readonly layout?: StyleProp<ViewStyle>;
}

/**
 * Pressable with the shared press feel: scale down on touch, spring back on release.
 * Reduced motion swaps the scale for a dim.
 */
export function Tap({ style, layout, children, scale = motion.pressScale, onPressIn, onPressOut, disabled, ...rest }: TapProps) {
  const pressed = useSharedValue(0);
  const reduced = useReducedMotion();
  const feel = useAnimatedStyle(() =>
    reduced ? { opacity: 1 - pressed.get() * 0.3 } : { transform: [{ scale: 1 - (1 - scale) * pressed.get() }] },
  );
  const down = (event: GestureResponderEvent) => {
    pressed.set(withTiming(1, { duration: motion.pressIn, easing: curve.out }));
    onPressIn?.(event);
  };
  const up = (event: GestureResponderEvent) => {
    pressed.set(withTiming(0, { duration: motion.pressOut, easing: curve.out }));
    onPressOut?.(event);
  };
  return (
    <Pressable {...rest} style={layout} disabled={disabled} onPressIn={down} onPressOut={up} accessibilityState={{ ...rest.accessibilityState, disabled: disabled === true }}>
      <Animated.View style={[style, feel, disabled === true ? { opacity: 0.4 } : null]}>{children}</Animated.View>
    </Pressable>
  );
}
