import type { ReactNode } from "react";
import { View } from "react-native";
import Animated from "react-native-reanimated";

import { swap } from "../motion";
import { Mono, Serif } from "../typography.tsx";

export function EmptyState({ title, detail, children }: { readonly title: string; readonly detail?: string | undefined; readonly children?: ReactNode }) {
  return (
    <Animated.View entering={swap} className="gap-3 px-[22px] py-10">
      <View className="h-px bg-line3" />
      <View className="gap-3" accessible accessibilityLabel={detail === undefined ? title : `${title} ${detail}`}>
        <Serif size="m" italic>
          {title}
        </Serif>
        {detail === undefined ? null : <Mono className="leading-5">{detail}</Mono>}
      </View>
      {children}
    </Animated.View>
  );
}
