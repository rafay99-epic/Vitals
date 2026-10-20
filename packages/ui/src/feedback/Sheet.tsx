import type { ReactNode } from "react";
import { Modal, Platform, Pressable, View } from "react-native";
import Animated, { FadeIn, SlideInDown } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { useWide } from "../layout/useWide.ts";
import { motion } from "../theme.ts";
import { Mono, Sans, Serif, type Tone } from "../typography.tsx";

const PHONE_EDGE = Platform.OS === "android" ? "border-t rounded-t-[28px]" : "border-t rounded-t-[26px]";

export interface SheetProps {
  readonly visible: boolean;
  readonly title: string;
  readonly detail?: string | undefined;
  readonly onClose: () => void;
  readonly children: ReactNode;
}

export function Sheet({ visible, title, detail, onClose, children }: SheetProps) {
  const insets = useSafeAreaInsets();
  const wide = useWide();
  return (
    <Modal visible={visible} transparent animationType="none" onRequestClose={onClose} statusBarTranslucent navigationBarTranslucent>
      <Animated.View entering={FadeIn.duration(motion.sheet)} className={`flex-1 bg-bg/70 ${wide ? "items-center justify-center" : "justify-end"}`}>
        <Pressable className="absolute inset-0" onPress={onClose} accessibilityRole="button" accessibilityLabel="Close" />
        <Animated.View
          entering={SlideInDown.duration(motion.sheet)}
          accessibilityViewIsModal
          className={`border-line2 bg-sheet pt-2.5 ${wide ? "w-[440px] rounded-xl border" : PHONE_EDGE}`}
          style={{ paddingBottom: wide ? 12 : Math.max(insets.bottom, 12) + 22 }}
        >
          {wide ? null : <View className="mb-3 h-1 w-[38px] self-center rounded-sm bg-line3" />}
          <View className="gap-1 px-[22px] pb-3.5">
            <Serif size="l" accessibilityRole="header">
              {title}
            </Serif>
            {detail === undefined ? null : <Mono>{detail}</Mono>}
          </View>
          {children}
          <Pressable onPress={onClose} accessibilityRole="button" className="min-h-14 justify-center border-t border-line px-[22px] active:bg-raise">
            <Sans tone="dim">Cancel</Sans>
          </Pressable>
        </Animated.View>
      </Animated.View>
    </Modal>
  );
}

export interface SheetActionProps {
  readonly label: string;
  readonly detail?: string | undefined;
  readonly tone?: Tone | undefined;
  readonly onPress: () => void;
}

export function SheetAction({ label, detail, tone = "ink", onPress }: SheetActionProps) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={detail === undefined ? label : `${label}, ${detail}`} className="min-h-14 flex-row items-center justify-between gap-3 border-t border-line px-[22px] active:bg-raise">
      <Serif size="s" tone={tone}>
        {label}
      </Serif>
      {detail === undefined ? null : <Mono className="text-right text-[10px]">{detail}</Mono>}
    </Pressable>
  );
}
