import { View } from "react-native";

import { Mono } from "../typography.tsx";

export interface StackPart {
  readonly key: string;
  readonly label: string;
  readonly value: number;
  readonly color: string;
  readonly display: string;
}

export function StackBar({ parts, total }: { readonly parts: ReadonlyArray<StackPart>; readonly total: number }) {
  const sum = Math.max(total, 1e-6);
  return (
    <View className="gap-3 px-[22px] py-3">
      <View className="h-2.5 flex-row gap-0.5" accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
        {parts.map((part) => (
          <View key={part.key} style={{ flex: Math.max(part.value, 0) / sum, backgroundColor: part.color }} />
        ))}
      </View>
      <View className="gap-1.5">
        {parts.map((part) => (
          <View key={part.key} className="flex-row items-center justify-between" accessible accessibilityLabel={`${part.label}, ${part.display}`}>
            <View className="flex-row items-center gap-2">
              <View className="h-2 w-2" style={{ backgroundColor: part.color }} />
              <Mono tone="ink2">{part.label}</Mono>
            </View>
            <Mono tone="ink">{part.display}</Mono>
          </View>
        ))}
      </View>
    </View>
  );
}
