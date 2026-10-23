import { haptics } from "@vitals/app/lib/haptics.ts";
import { useEffect, useRef } from "react";
import { Pressable, StyleSheet, View } from "react-native";
import Animated, { Easing, interpolateColor, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";

import { color, font, motion } from "./tokens.ts";

export interface HoldProps {
  readonly label: string;
  readonly onCommit: () => void;
  readonly small?: boolean;
  readonly disabled?: boolean;
}

/**
 * Press and hold to confirm. Used only for actions that lose work or end a session:
 * shut down, restart, log out, quit, force quit, unpair. Letting go early cancels.
 * Screen readers get a direct "activate" action, since they cannot hold.
 */
export function Hold({ label, onCommit, small = false, disabled = false }: HoldProps) {
  const progress = useSharedValue(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(
    () => () => {
      if (timer.current !== null) clearTimeout(timer.current);
    },
    [],
  );

  // Losing permission (or the target) mid-hold cancels it, so a destructive commit can't land late.
  useEffect(() => {
    if (!disabled || timer.current === null) return;
    clearTimeout(timer.current);
    timer.current = null;
    progress.set(0);
  }, [disabled, progress]);

  const commit = () => {
    timer.current = null;
    progress.set(0);
    haptics.heavy();
    onCommit();
  };
  const start = () => {
    if (disabled || timer.current !== null) return;
    haptics.soft();
    progress.set(withTiming(1, { duration: motion.hold, easing: Easing.linear }));
    timer.current = setTimeout(commit, motion.hold);
  };
  const stop = () => {
    if (timer.current === null) return;
    clearTimeout(timer.current);
    timer.current = null;
    progress.set(withTiming(0, { duration: 180 }));
  };

  const fill = useAnimatedStyle(() => ({ transform: [{ scaleX: progress.get() }] }));
  const text = useAnimatedStyle(() => ({ color: interpolateColor(progress.get(), [0, 0.45], [color.red, color.bg]) }));

  return (
    <Pressable
      onPressIn={start}
      onPressOut={stop}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint="Press and hold to confirm"
      accessibilityState={{ disabled }}
      accessibilityActions={[{ name: "activate", label }]}
      onAccessibilityAction={() => {
        if (!disabled) commit();
      }}
      style={[styles.box, small ? styles.small : null, disabled ? styles.off : null]}
    >
      <View style={StyleSheet.absoluteFill} pointerEvents="none">
        <Animated.View style={[styles.fill, fill]} />
      </View>
      <Animated.Text maxFontSizeMultiplier={1.3} style={[styles.label, small ? styles.smallLabel : null, text]}>
        {label}
      </Animated.Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  box: {
    height: 56,
    marginHorizontal: 16,
    marginTop: 8,
    borderRadius: 16,
    borderWidth: 1.5,
    borderColor: color.red,
    overflow: "hidden",
    alignItems: "center",
    justifyContent: "center",
  },
  small: { height: 46, borderWidth: 1, opacity: 0.85 },
  off: { opacity: 0.35 },
  fill: { flex: 1, backgroundColor: color.red, transformOrigin: "left" },
  label: { fontFamily: font.sansSemibold, fontSize: 15, color: color.red },
  smallLabel: { fontSize: 13 },
});
