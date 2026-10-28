import { Store } from "@vitals/client-runtime";
import { useStore } from "@vitals/app/state/useStore.ts";
import { type ReactNode, useEffect } from "react";
import { StyleSheet, View } from "react-native";
import Animated, { FadeOut, SlideInDown } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { T } from "./Text.tsx";
import { Tap } from "./Tap.tsx";
import { color, curve, DOCK_BOTTOM, DOCK_HEIGHT, motion } from "./tokens.ts";

export type ToastTone = "ok" | "bad";

interface Message {
  readonly id: number;
  readonly text: string;
  readonly tone: ToastTone;
  readonly action: { readonly label: string; readonly run: () => void } | null;
}

const current = new Store<Message | null>(null);
let nextId = 0;
let timer: ReturnType<typeof setTimeout> | null = null;

export interface ToastOptions {
  readonly tone?: ToastTone;
  readonly action?: string;
  readonly onAction?: () => void;
}

/** One toast at a time, above the dock. Every action that has no other visible result ends here. */
export const toast = {
  show(text: string, options: ToastOptions = {}): void {
    const action = options.action !== undefined && options.onAction !== undefined ? { label: options.action, run: options.onAction } : null;
    const message: Message = { id: ++nextId, text, tone: options.tone ?? "ok", action };
    current.set(message);
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(() => {
      if (current.get() === message) current.set(null);
    }, motion.toastHold);
  },
  hide(): void {
    current.set(null);
  },
};

/** Bottom stack above the dock: a pinned strip (pending orders) and the transient toast. */
export function ToastHost({ pinned }: { readonly pinned?: ReactNode }) {
  const message = useStore(current);
  const insets = useSafeAreaInsets();
  // The host unmounts on unpair: drop the message too, or it would come back with no timer to clear it.
  useEffect(() => () => {
    if (timer !== null) clearTimeout(timer);
    current.set(null);
  }, []);
  return (
    <View pointerEvents="box-none" style={[styles.host, { bottom: insets.bottom + DOCK_BOTTOM + DOCK_HEIGHT + 10 }]}>
      {message === null ? null : (
        <Animated.View
          key={message.id}
          entering={SlideInDown.duration(motion.toastIn).easing(curve.out)}
          exiting={FadeOut.duration(motion.toastOut)}
          accessibilityRole="alert"
          accessibilityLiveRegion="polite"
          style={[styles.toast, message.tone === "bad" ? styles.bad : null]}
        >
          <T v="strong" color={color.bg} style={styles.text}>
            {message.text}
          </T>
          {message.action === null ? null : (
            <Tap
              hitSlop={12}
              accessibilityRole="button"
              onPress={() => {
                const run = message.action?.run;
                current.set(null);
                run?.();
              }}
            >
              <T v="strong" color={color.bg} style={styles.action}>
                {message.action.label}
              </T>
            </Tap>
          )}
        </Animated.View>
      )}
      {pinned}
    </View>
  );
}

/**
 * A strip pinned above the dock that stays while something is under way (a countdown, a transfer).
 * Its text updates in place; only the entrance and exit animate.
 */
export function Strip({ text, action, onAction, tone = "ink" }: { readonly text: string; readonly action?: string; readonly onAction?: () => void; readonly tone?: "ink" | "warn" }) {
  return (
    <Animated.View
      entering={SlideInDown.duration(motion.toastIn).easing(curve.out)}
      exiting={FadeOut.duration(motion.toastOut)}
      accessibilityRole="alert"
      style={[styles.toast, tone === "warn" ? styles.warn : null]}
    >
      <T v="strong" color={color.bg} style={styles.text} numberOfLines={2}>
        {text}
      </T>
      {action === undefined || onAction === undefined ? null : (
        <Tap onPress={onAction} accessibilityRole="button" hitSlop={12}>
          <T v="strong" color={color.bg} style={styles.action}>
            {action}
          </T>
        </Tap>
      )}
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  host: { position: "absolute", left: 14, right: 14, gap: 8 },
  toast: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    backgroundColor: color.ink,
    borderRadius: 16,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  bad: { backgroundColor: color.red },
  warn: { backgroundColor: color.orange },
  text: { flex: 1 },
  action: { textDecorationLine: "underline" },
});
