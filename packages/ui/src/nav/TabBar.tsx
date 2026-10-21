import type { ReactNode } from "react";
import { Platform, Pressable, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { channels, colors } from "../theme.ts";
import { Mono, Serif } from "../typography.tsx";
import { Glyph, type GlyphName, Mark } from "./Glyph";

export interface TabItem {
  readonly key: string;
  readonly label: string;
  readonly glyph: GlyphName;
  readonly badge?: boolean | undefined;
}

export interface TabBarProps {
  readonly items: ReadonlyArray<TabItem>;
  readonly active: string;
  readonly onSelect: (key: string) => void;
  readonly rail?: boolean | undefined;
  readonly footer?: ReactNode;
}

const ANDROID = Platform.OS === "android";

function TabButton({ item, on, rail, onSelect }: { readonly item: TabItem; readonly on: boolean; readonly rail: boolean; readonly onSelect: (key: string) => void }) {
  const idle = rail ? colors.dim : colors.mute;
  return (
    <Pressable
      onPress={() => onSelect(item.key)}
      accessibilityRole="tab"
      accessibilityLabel={item.badge === true ? `${item.label}, alarm` : item.label}
      accessibilityState={{ selected: on }}
      className={rail ? "min-h-11 flex-row items-center gap-3 px-[22px] active:bg-raise" : "min-h-12 w-16 items-center gap-1.5"}
    >
      <View className={!rail && ANDROID && on ? "rounded-xl bg-line2 px-3 py-0.5" : "py-0.5"}>
        <Glyph name={item.glyph} color={on ? channels.pulse.color : idle} />
        {item.badge === true ? <View className="absolute -right-1 -top-0.5 h-1.5 w-1.5 bg-alarm-high" /> : null}
      </View>
      <Mono tone={on ? "ink" : "dim"} className={rail ? "text-xs" : "text-[10px]"}>
        {item.label}
      </Mono>
    </Pressable>
  );
}

export function TabBar({ items, active, onSelect, rail = false, footer }: TabBarProps) {
  const insets = useSafeAreaInsets();
  const buttons = items.map((item) => <TabButton key={item.key} item={item} on={item.key === active} rail={rail} onSelect={onSelect} />);
  if (!rail) {
    return (
      <View className="flex-row justify-around border-t border-line bg-bg px-1.5 pt-2.5" style={{ paddingBottom: Math.max(insets.bottom, 10) }} accessibilityRole="tablist">
        {buttons}
      </View>
    );
  }
  return (
    <View className="w-[220px] border-r border-line py-[22px]" accessibilityRole="tablist">
      <View className="flex-row items-center gap-2.5 px-[22px] pb-6">
        <Mark width={34} />
        <Serif size="m">Vitals</Serif>
      </View>
      {buttons}
      <View className="mt-auto px-[22px]">{footer}</View>
    </View>
  );
}
