import { Pressable } from "react-native";
import Animated, { FadeInDown, FadeOut } from "react-native-reanimated";

import { motion } from "../theme.ts";
import { Sans } from "../typography.tsx";

export type ToastTone = "ok" | "bad";

const BOX: Record<ToastTone, string> = { ok: "bg-ink", bad: "bg-alarm-high" };

export interface ToastProps {
  readonly message: string;
  readonly tone: ToastTone;
  readonly action?: string | undefined;
  readonly onAction?: (() => void) | undefined;
}

export function Toast({ message, tone, action, onAction }: ToastProps) {
  return (
    <Animated.View
      entering={FadeInDown.duration(motion.toastIn)}
      exiting={FadeOut.duration(motion.toastIn)}
      accessibilityRole="alert"
      accessibilityLiveRegion="polite"
      className={`absolute bottom-4 left-3.5 right-3.5 z-10 flex-row items-center justify-between gap-3 px-4 py-3.5 ${BOX[tone]}`}
    >
      <Sans size="small" weight="medium" tone="black" className="flex-1">
        {message}
      </Sans>
      {action === undefined || onAction === undefined ? null : (
        <Pressable onPress={onAction} accessibilityRole="button" hitSlop={10}>
          <Sans size="small" weight="semibold" tone="black">
            {action}
          </Sans>
        </Pressable>
      )}
    </Animated.View>
  );
}
