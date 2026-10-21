import type { ReactNode } from "react";
import { View } from "react-native";

import { useWide } from "./useWide.ts";

export function Columns({ main, side }: { readonly main: ReactNode; readonly side: ReactNode }) {
  if (!useWide()) {
    return (
      <View>
        {main}
        {side}
      </View>
    );
  }
  return (
    <View className="flex-row items-start">
      <View className="flex-1 border-r border-line">{main}</View>
      <View className="w-[420px]">{side}</View>
    </View>
  );
}
