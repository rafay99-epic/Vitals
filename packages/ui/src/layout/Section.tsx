import type { ReactNode } from "react";
import { View } from "react-native";
import Animated from "react-native-reanimated";

import { rise, settle } from "../motion";
import { Mono, Tag } from "../typography.tsx";

export function SectionHeader({ title, trailing }: { readonly title: string; readonly trailing?: ReactNode }) {
  return (
    <View className="flex-row items-baseline justify-between px-[22px] pb-2 pt-6">
      <Tag accessibilityRole="header">{title}</Tag>
      {typeof trailing === "string" ? <Mono>{trailing}</Mono> : trailing}
    </View>
  );
}

export function Section({ title, trailing, children }: { readonly title: string; readonly trailing?: ReactNode; readonly children: ReactNode }) {
  return (
    <Animated.View entering={rise()} layout={settle}>
      <SectionHeader title={title} trailing={trailing} />
      <View className="border-b border-line">{children}</View>
    </Animated.View>
  );
}
