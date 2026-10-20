import { Pressable, View } from "react-native";

import { Spark } from "../channel/Spark";
import type { Channel } from "../theme.ts";
import { Mono, Serif } from "../typography.tsx";

export interface BedRowProps {
  readonly bed: number;
  readonly name: string;
  readonly meta: string;
  readonly channel: Channel;
  readonly trend: ReadonlyArray<number>;
  readonly value: string;
  readonly unit: string;
  readonly paused?: boolean | undefined;
  readonly selected?: boolean | undefined;
  readonly onPress: () => void;
  readonly accessibilityLabel: string;
}

export function BedRow({ bed, name, meta, channel, trend, value, unit, paused = false, selected = false, onPress, accessibilityLabel }: BedRowProps) {
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ selected }}
      className={`min-h-[58px] flex-row items-center gap-2 border-t border-line py-2 pl-[22px] pr-[22px] active:bg-raise ${selected ? "border-l-2 border-l-ink bg-raise" : ""}`}
    >
      <Mono tone="mute" className="w-[22px] text-[10px]">
        {String(bed).padStart(2, "0")}
      </Mono>
      <View className="flex-1 gap-0.5">
        <Serif size="s" tone={paused ? "dim" : "ink"} numberOfLines={1}>
          {name}
        </Serif>
        <Mono className="text-[10px]" numberOfLines={1}>
          {paused ? `${meta} · paused` : meta}
        </Mono>
      </View>
      <Spark channel={channel} values={trend} width={56} height={24} quiet={paused} />
      <View className="w-12 items-end">
        <Serif size="s" tone={paused ? "dim" : "ink"}>
          {value}
        </Serif>
        <Mono className="text-[9.5px]">{unit}</Mono>
      </View>
    </Pressable>
  );
}

export function WardHeader({ name, totals }: { readonly name: string; readonly totals: string }) {
  return (
    <View className="flex-row items-baseline justify-between px-[22px] pb-2 pt-5" accessible accessibilityRole="header" accessibilityLabel={`${name}, ${totals}`}>
      <Serif size="m" italic>
        {name}
      </Serif>
      <Mono className="text-[10px]">{totals}</Mono>
    </View>
  );
}
