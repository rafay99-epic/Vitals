import { Pressable, View } from "react-native";
import Animated, { SlideInUp } from "react-native-reanimated";

import { motion } from "../theme.ts";
import { Mono, Sans, Serif } from "../typography.tsx";

export type AlarmLevel = "high" | "medium" | "low";

const LEVEL: Record<AlarmLevel, string> = { high: "bg-alarm-high", medium: "bg-alarm-medium", low: "bg-alarm-low" };

export interface AlarmBannerProps {
  readonly level: AlarmLevel;
  readonly title: string;
  readonly detail?: string | undefined;
  readonly action?: string | undefined;
  readonly onAction?: (() => void) | undefined;
}

export function AlarmBanner({ level, title, detail, action, onAction }: AlarmBannerProps) {
  return (
    <Animated.View
      entering={SlideInUp.duration(motion.alarmIn)}
      accessibilityRole="alert"
      accessibilityLiveRegion="assertive"
      className={`flex-row items-center gap-3 py-3 pl-[22px] pr-[18px] ${LEVEL[level]}`}
    >
      <View className="flex-1">
        <Serif size="s" italic tone="black">
          {title}
        </Serif>
        {detail === undefined ? null : (
          <Mono tone="black" className="mt-0.5 text-[10.5px]">
            {detail}
          </Mono>
        )}
      </View>
      {action === undefined || onAction === undefined ? null : (
        <Pressable onPress={onAction} accessibilityRole="button" accessibilityLabel={action} className="min-h-10 justify-center bg-bg px-3.5 active:opacity-80">
          <Sans size="small" weight="medium">
            {action}
          </Sans>
        </Pressable>
      )}
    </Animated.View>
  );
}
