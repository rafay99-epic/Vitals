import type { ReactNode } from "react";
import { Platform, Pressable, View } from "react-native";

import { Mono, Sans, Serif, type Tone } from "../typography.tsx";

export type LinkTone = "live" | "quiet" | "warn" | "off";

const LINK: Record<LinkTone, { readonly dot: string; readonly tone: Tone }> = {
  live: { dot: "●", tone: "pulse" },
  quiet: { dot: "○", tone: "dim" },
  warn: { dot: "○", tone: "alarmMedium" },
  off: { dot: "○", tone: "mute" },
};

export interface ScreenHeaderProps {
  readonly who: string;
  readonly link: string;
  readonly linkTone: LinkTone;
  readonly word: ReactNode;
  readonly wordTone?: Tone | undefined;
  readonly meta?: ReactNode;
  readonly metaTone?: Tone | undefined;
}

export function ScreenHeader({ who, link, linkTone, word, wordTone = "ink", meta, metaTone = "dim" }: ScreenHeaderProps) {
  const status = LINK[linkTone];
  return (
    <View className="px-[22px] pb-3 pt-1">
      <View className="flex-row items-baseline justify-between gap-3" accessibilityLiveRegion="polite">
        <Mono tone="ink2" numberOfLines={1} className="flex-1">
          {who}
        </Mono>
        <Mono tone={status.tone}>{`${status.dot} ${link}`}</Mono>
      </View>
      <Serif size="state" italic tone={wordTone} accessibilityRole="header" className="mt-1.5">
        {word}
      </Serif>
      {meta === undefined ? null : (
        <Mono tone={metaTone} className="mt-1">
          {meta}
        </Mono>
      )}
    </View>
  );
}

export function BackHeader({ parent, onBack }: { readonly parent: string; readonly onBack: () => void }) {
  return (
    <Pressable onPress={onBack} accessibilityRole="button" accessibilityLabel={`Back to ${parent}`} hitSlop={12} className="min-h-11 flex-row items-center gap-2 self-start px-4">
      <View className="h-2.5 w-2.5 -rotate-45 border-l-[1.5px] border-t-[1.5px] border-ink2" />
      {Platform.OS === "android" ? null : (
        <Sans size="small" tone="ink2">
          {parent}
        </Sans>
      )}
    </Pressable>
  );
}
