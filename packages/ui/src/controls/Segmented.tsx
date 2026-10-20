import { Pressable, View } from "react-native";

import { Tag } from "../typography.tsx";
import type { Option } from "./Chips.tsx";

export function Segmented<T extends string>({
  options,
  value,
  onChange,
  inset = true,
}: {
  readonly options: ReadonlyArray<Option<T>>;
  readonly value: T;
  readonly onChange: (value: T) => void;
  readonly inset?: boolean | undefined;
}) {
  return (
    <View className={`flex-row gap-5 border-b border-line ${inset ? "px-[22px]" : ""}`} accessibilityRole="tablist">
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={option.value}
            onPress={() => onChange(option.value)}
            accessibilityRole="tab"
            accessibilityState={{ selected }}
            className={`-mb-px min-h-11 justify-center border-b-[1.5px] ${selected ? "border-ink" : "border-transparent"}`}
          >
            <Tag tone={selected ? "ink" : "dim"}>{option.label}</Tag>
          </Pressable>
        );
      })}
    </View>
  );
}
