import { Store } from "@vitals/client-runtime";
import { type ComponentType, type ReactNode, useEffect, useRef, useState } from "react";
import { BackHandler, Keyboard, type LayoutChangeEvent, Pressable, ScrollView, StyleSheet, useWindowDimensions, View } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { useAnimatedKeyboard, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { scheduleOnRN } from "react-native-worklets";

import { T } from "./Text.tsx";
import { Tap } from "./Tap.tsx";
import { color, curve, motion } from "./tokens.ts";

interface Entry {
  readonly id: number;
  readonly Content: ComponentType;
}

const wanted = new Store<Entry | null>(null);
let nextId = 0;

/**
 * Imperative sheet API. `sheet.open(Component)` slides a sheet up; opening while one is
 * showing closes the current one first. Content components render their own header.
 */
export const sheet = {
  open: (Content: ComponentType): void => {
    Keyboard.dismiss();
    wanted.set({ id: ++nextId, Content });
  },
  close: (): void => wanted.set(null),
  showing: (): boolean => wanted.get() !== null,
};

const DISMISS_DISTANCE = 90;
const DISMISS_VELOCITY = 800;

/** Renders the active sheet over everything. Mount once, above the tabs. */
export function SheetHost() {
  const [shown, setShown] = useState<Entry | null>(null);
  const insets = useSafeAreaInsets();
  const { height: screen } = useWindowDimensions();
  const keyboard = useAnimatedKeyboard();
  const progress = useSharedValue(0);
  const drag = useSharedValue(0);
  const size = useSharedValue(screen);
  const current = useRef<Entry | null>(null);
  const opening = useRef(false);
  // Content taller than the sheet's cap scrolls instead (big text, short screens). Dragging the sheet
  // away is off then, so the two gestures never fight; the scrim, back and Cancel still close it.
  const [overflow, setOverflow] = useState(false);
  const viewport = useRef(0);
  const content = useRef(0);
  const checkOverflow = () => setOverflow(content.current > viewport.current + 1);

  useEffect(() => {
    const show = (entry: Entry | null) => {
      current.current = entry;
      opening.current = entry !== null;
      drag.set(0);
      setOverflow(false);
      setShown(entry);
    };
    const settle = () => show(wanted.get());
    // A sheet opened before this mounted, like one asked for at launch.
    if (wanted.get() !== null) show(wanted.get());
    return wanted.subscribe(() => {
      const next = wanted.get();
      if (current.current === null) {
        if (next !== null) show(next);
        return;
      }
      if (next?.id === current.current.id) return;
      progress.set(
        withTiming(0, { duration: motion.sheetOut, easing: curve.tray }, (finished) => {
          if (finished === true) scheduleOnRN(settle);
        }),
      );
    });
  }, [progress, drag]);

  useEffect(() => {
    if (shown === null) return;
    const subscription = BackHandler.addEventListener("hardwareBackPress", () => {
      sheet.close();
      return true;
    });
    return () => subscription.remove();
  }, [shown]);

  const measure = (event: LayoutChangeEvent) => {
    size.set(event.nativeEvent.layout.height);
    if (!opening.current) return;
    opening.current = false;
    progress.set(withTiming(1, { duration: motion.sheetIn, easing: curve.tray }));
  };

  const close = sheet.close;
  const pan = Gesture.Pan()
    .enabled(!overflow)
    .activeOffsetY(8)
    .failOffsetX([-24, 24])
    .onUpdate((event) => {
      drag.set(Math.max(0, event.translationY));
    })
    .onEnd((event) => {
      if (drag.get() > DISMISS_DISTANCE || event.velocityY > DISMISS_VELOCITY) {
        scheduleOnRN(close);
        return;
      }
      drag.set(withTiming(0, { duration: motion.sheetOut, easing: curve.tray }));
    });

  const body = useAnimatedStyle(() => ({
    transform: [{ translateY: (1 - progress.get()) * size.get() + drag.get() - keyboard.height.get() }],
  }));
  const scrim = useAnimatedStyle(() => ({
    opacity: progress.get() * Math.max(0, 1 - drag.get() / Math.max(1, size.get())),
  }));

  if (shown === null) return null;
  const Content = shown.Content;
  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="box-none">
      <Animated.View style={[StyleSheet.absoluteFill, styles.scrim, scrim]}>
        <Pressable style={StyleSheet.absoluteFill} onPress={sheet.close} accessibilityRole="button" accessibilityLabel="Close" />
      </Animated.View>
      <GestureDetector gesture={pan}>
        <Animated.View
          key={shown.id}
          onLayout={measure}
          accessibilityViewIsModal
          style={[styles.sheet, { maxHeight: screen - insets.top - 24, paddingBottom: Math.max(insets.bottom, 12) + 12 }, body]}
        >
          <View style={styles.grab} />
          <ScrollView
            bounces={false}
            scrollEnabled={overflow}
            keyboardShouldPersistTaps="handled"
            onLayout={(event) => {
              viewport.current = event.nativeEvent.layout.height;
              checkOverflow();
            }}
            onContentSizeChange={(_, height) => {
              content.current = height;
              checkOverflow();
            }}
          >
            <Content />
          </ScrollView>
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

/** Title block at the top of a sheet. */
export function SheetHeader({ title, detail }: { readonly title: string; readonly detail?: string | undefined }) {
  return (
    <View style={styles.header}>
      <T v="heading" accessibilityRole="header">
        {title}
      </T>
      {detail === undefined ? null : (
        <T v="small" style={styles.detail}>
          {detail}
        </T>
      )}
    </View>
  );
}

/** Quiet text button at the bottom of a sheet. Closes it by default. */
export function SheetCancel({ label = "Cancel", onPress = sheet.close }: { readonly label?: string; readonly onPress?: () => void }) {
  return (
    <Tap onPress={onPress} accessibilityRole="button" style={styles.cancel}>
      <T v="body" color={color.dim}>
        {label}
      </T>
    </Tap>
  );
}

/** Padded body text inside a sheet. */
export function SheetNote({ children }: { readonly children: ReactNode }) {
  return (
    <T v="body" color={color.ink2} style={styles.note}>
      {children}
    </T>
  );
}

const styles = StyleSheet.create({
  scrim: { backgroundColor: color.scrim },
  sheet: {
    position: "absolute",
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: color.s2,
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderColor: color.line2,
    paddingTop: 10,
  },
  grab: { width: 36, height: 5, borderRadius: 3, backgroundColor: "#3a3a3a", alignSelf: "center", marginBottom: 14 },
  header: { paddingHorizontal: 20, paddingBottom: 14 },
  detail: { marginTop: 4 },
  cancel: { alignItems: "center", paddingVertical: 14 },
  note: { paddingHorizontal: 20, paddingTop: 8, paddingBottom: 14 },
});
