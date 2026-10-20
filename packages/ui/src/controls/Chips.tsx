import { Pressable, View } from "react-native";

import { Serif } from "../typography.tsx";

export interface Option<T extends string> {
  readonly value: T;
  readonly label: string;
}

export function Chips<T extends string>({
  options,
  value,
  onChange,
  disabled = false,
}: {
  readonly options: ReadonlyArray<Option<T>>;
  readonly value: T | null;
  readonly onChange: (value: T) => void;
  readonly disabled?: boolean | undefined;
}) {
  return (
    <View className="flex-row gap-4" accessibilityRole="radiogroup">
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={option.value}
            onPress={() => onChange(option.value)}
            disabled={disabled}
            hitSlop={8}
            accessibilityRole="radio"
            accessibilityState={{ selected, disabled }}
            className="min-h-11 justify-center"
          >
            <Serif size="s" tone={selected ? "pulse" : "dim"}>
              {option.label}
            </Serif>
          </Pressable>
        );
      })}
    </View>
  );
}
