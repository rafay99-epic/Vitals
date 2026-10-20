import { View } from "react-native";

import { Mono, Serif, type Tone } from "../typography.tsx";

export interface KeyValue {
  readonly key: string;
  readonly value: string;
  readonly unit?: string | undefined;
  readonly tone?: Tone | undefined;
}

export function KeyValueGrid({ items }: { readonly items: ReadonlyArray<KeyValue> }) {
  return (
    <View className="flex-row flex-wrap border-t border-line">
      {items.map((item, index) => (
        <View
          key={item.key}
          accessible
          accessibilityLabel={`${item.key}, ${item.value}${item.unit === undefined ? "" : ` ${item.unit}`}`}
          className={`w-1/2 gap-1 border-b border-line px-[22px] py-3.5 ${index % 2 === 0 ? "border-r" : ""}`}
        >
          <Mono className="text-[10px]">{item.key}</Mono>
          <View className="flex-row items-baseline">
            <Serif size="m" tone={item.tone}>
              {item.value}
            </Serif>
            {item.unit === undefined ? null : <Mono tone="ink2" className="ml-1 text-[10px]">{item.unit}</Mono>}
          </View>
        </View>
      ))}
    </View>
  );
}
