import type { ReactNode } from "react";
import { Pressable, View } from "react-native";
import Animated from "react-native-reanimated";

import { rise, settle } from "../motion";
import type { SeriesSource } from "../series.ts";
import { type Channel, channels } from "../theme.ts";
import { Mono, Serif, Tag } from "../typography.tsx";
import { Trace } from "./Trace";

export type ChannelState = "normal" | "elevated" | "alarm" | "flat" | "waiting";

type Size = "full" | "compact" | "lane";

const SIZE: Record<Size, { readonly row: string; readonly trace: number; readonly value: "l" | "m" | "xl2"; readonly lane: boolean }> = {
  full: { row: "h-[88px]", trace: 54, value: "l", lane: false },
  compact: { row: "h-16", trace: 36, value: "m", lane: false },
  lane: { row: "h-[76px]", trace: 60, value: "xl2", lane: true },
};

const FLAG: Record<ChannelState, { readonly text: string; readonly className: string } | null> = {
  normal: null,
  elevated: { text: "ELEV", className: "bg-alarm-medium" },
  alarm: { text: "HIGH", className: "bg-alarm-high" },
  flat: null,
  waiting: null,
};

export interface ChannelRowProps {
  readonly channel: Channel;
  readonly source: SeriesSource;
  readonly pair?: SeriesSource | undefined;
  readonly value: ReactNode;
  readonly unit?: string | undefined;
  readonly min?: number | undefined;
  readonly max?: number | null | undefined;
  readonly state?: ChannelState | undefined;
  readonly size?: Size | undefined;
  readonly onPress?: (() => void) | undefined;
  readonly accessibilityHint?: string | undefined;
  readonly order?: number | undefined;
}

export function ChannelRow({ channel, source, pair, value, unit, min, max, state = "normal", size = "full", onPress, accessibilityHint, order = 0 }: ChannelRowProps) {
  const spec = channels[channel];
  const layout = SIZE[size];
  const quiet = state === "flat" || state === "waiting";
  const flag = FLAG[state];
  const tone = quiet ? "mute" : channel;
  return (
    <Animated.View entering={rise(order)} layout={settle}>
      <Pressable
        onPress={onPress}
        disabled={onPress === undefined}
        accessibilityRole={onPress === undefined ? "text" : "button"}
        accessibilityHint={accessibilityHint}
        className={`flex-row items-center gap-2.5 border-t border-line pl-[22px] pr-5 active:bg-raise ${layout.row} ${state === "alarm" ? "bg-alarm-high/10" : ""}`}
      >
        <View className={layout.lane ? "w-24" : "w-[58px]"}>
          <Tag tone={tone}>{spec.tag}</Tag>
          <Mono tone={quiet ? "mute" : "dim"} className="text-[10px]">
            {spec.label}
          </Mono>
          {flag === null ? null : (
            <View className={`mt-1 self-start px-1 ${flag.className}`}>
              <Tag tone="black">{flag.text}</Tag>
            </View>
          )}
        </View>
        <View className="flex-1">
          <Trace channel={channel} source={source} pair={pair} height={layout.trace} min={min} max={max} flat={quiet} beats={layout.lane ? spec.wideBeats : undefined} />
        </View>
        <View className={`flex-row items-baseline justify-end ${layout.lane ? "min-w-36" : "min-w-[74px]"}`}>
          <Serif size={layout.value} tone={tone}>
            {state === "waiting" ? "--" : value}
          </Serif>
          {unit === undefined ? null : (
            <Mono tone={quiet ? "mute" : channel} className="ml-0.5 text-[10px]">
              {unit}
            </Mono>
          )}
        </View>
      </Pressable>
    </Animated.View>
  );
}
