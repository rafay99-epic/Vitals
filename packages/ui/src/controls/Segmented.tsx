import { Pressable, Text, View } from "react-native";

export function Segmented<T extends string>({
  options,
  value,
  onChange,
}: {
  readonly options: ReadonlyArray<{ readonly value: T; readonly label: string }>;
  readonly value: T;
  readonly onChange: (value: T) => void;
}) {
  return (
    <View className="flex-row border border-line" accessibilityRole="tablist">
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={option.value}
            onPress={() => onChange(option.value)}
            accessibilityRole="tab"
            accessibilityState={{ selected }}
            className={`min-h-9 flex-1 items-center justify-center ${selected ? "bg-ink" : ""}`}
          >
            <Text className={`font-mono text-xs ${selected ? "text-canvas" : "text-dim"}`}>{option.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}
