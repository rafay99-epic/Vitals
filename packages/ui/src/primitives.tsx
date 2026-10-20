import type { ReactNode } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

export type Tone = "ink" | "ok" | "warn" | "bad" | "dim" | "accent";

export const toneText: Record<Tone, string> = {
  ink: "text-ink",
  ok: "text-ok",
  warn: "text-warn",
  bad: "text-bad",
  dim: "text-dim",
  accent: "text-accent",
};

const toneBorder: Record<Tone, string> = {
  ink: "border-ink",
  ok: "border-ok",
  warn: "border-warn",
  bad: "border-bad",
  dim: "border-dim",
  accent: "border-accent",
};

export function Screen({ children, insetTop = true }: { readonly children: ReactNode; readonly insetTop?: boolean }) {
  const insets = useSafeAreaInsets();
  return (
    <ScrollView
      className="flex-1 bg-canvas"
      contentContainerClassName="px-4 pb-16"
      contentContainerStyle={{ paddingTop: (insetTop ? insets.top : 0) + 8 }}
      keyboardShouldPersistTaps="handled"
    >
      {children}
    </ScrollView>
  );
}

export function Section({ title, trailing, children }: { readonly title: string; readonly trailing?: ReactNode; readonly children: ReactNode }) {
  return (
    <View className="mt-6">
      <View className="mb-2 flex-row items-center justify-between">
        <Text className="font-mono text-[11px] uppercase tracking-widest text-mute">{title}</Text>
        {trailing}
      </View>
      {children}
    </View>
  );
}

export function Divider() {
  return <View className="h-px bg-line" />;
}

export function Row({
  label,
  value,
  detail,
  onPress,
  tone = "ink",
}: {
  readonly label: string;
  readonly value?: string | undefined;
  readonly detail?: string | undefined;
  readonly onPress?: (() => void) | undefined;
  readonly tone?: Tone;
}) {
  const body = (
    <View className="min-h-11 flex-row items-center justify-between border-b border-line py-2.5">
      <View className="flex-1 pr-3">
        <Text className="text-[15px] text-ink">{label}</Text>
        {detail === undefined ? null : <Text className="mt-0.5 text-xs text-dim">{detail}</Text>}
      </View>
      {value === undefined ? null : <Text className={`font-mono text-[15px] ${toneText[tone]}`}>{value}</Text>}
    </View>
  );
  return onPress === undefined ? body : <Pressable onPress={onPress} accessibilityRole="button">{body}</Pressable>;
}

export function Stat({ label, value, unit, tone = "ink" }: { readonly label: string; readonly value: string; readonly unit?: string; readonly tone?: Tone }) {
  return (
    <View className="min-w-[72px]">
      <Text className="font-mono text-[10px] uppercase tracking-widest text-mute">{label}</Text>
      <Text className={`mt-0.5 font-mono text-2xl ${toneText[tone]}`}>
        {value}
        {unit === undefined ? null : <Text className="text-sm text-dim"> {unit}</Text>}
      </Text>
    </View>
  );
}

export function Banner({ text, tone = "warn", action, onAction }: { readonly text: string; readonly tone?: Tone; readonly action?: string; readonly onAction?: () => void }) {
  return (
    <View className={`mt-3 flex-row items-center justify-between border-l-2 py-1.5 pl-3 ${toneBorder[tone]}`}>
      <Text className={`flex-1 text-sm ${toneText[tone]}`}>{text}</Text>
      {action === undefined || onAction === undefined ? null : (
        <Pressable onPress={onAction} accessibilityRole="button" hitSlop={10}>
          <Text className="pl-3 text-sm font-semibold text-ink">{action}</Text>
        </Pressable>
      )}
    </View>
  );
}

export function TextButton({ label, onPress, tone = "ink", disabled = false }: { readonly label: string; readonly onPress: () => void; readonly tone?: Tone; readonly disabled?: boolean }) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      className={`min-h-11 items-center justify-center border border-line px-4 ${disabled ? "opacity-40" : "active:bg-line"}`}
    >
      <Text className={`text-[15px] font-medium ${toneText[tone]}`}>{label}</Text>
    </Pressable>
  );
}
