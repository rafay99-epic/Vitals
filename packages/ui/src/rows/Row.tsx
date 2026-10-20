import type { ReactNode } from "react";
import { Pressable, View } from "react-native";

import { Mono, Sans, Serif, type Tone } from "../typography.tsx";

export interface RowProps {
  readonly label: string;
  readonly detail?: string | undefined;
  readonly value?: string | undefined;
  readonly valueTone?: Tone | undefined;
  readonly trailing?: ReactNode;
  readonly tone?: Tone | undefined;
  readonly plain?: boolean | undefined;
  readonly locked?: boolean | undefined;
  readonly onPress?: (() => void) | undefined;
  readonly accessibilityLabel?: string | undefined;
}

export function Row({ label, detail, value, valueTone = "ink", trailing, tone = "ink", plain = false, locked = false, onPress, accessibilityLabel }: RowProps) {
  const action = onPress !== undefined;
  const pressable = action && !locked;
  return (
    <Pressable
      onPress={onPress}
      disabled={!pressable}
      accessible={action || trailing === undefined}
      accessibilityRole={action ? "button" : "text"}
      accessibilityLabel={accessibilityLabel ?? [label, value, detail].filter((part) => part !== undefined).join(", ")}
      accessibilityState={{ disabled: locked }}
      className={`min-h-14 flex-row items-center gap-3.5 border-t border-line px-[22px] py-2.5 active:bg-raise ${locked ? "opacity-45" : ""}`}
    >
      <View className="min-w-24 flex-1">
        {plain ? (
          <Sans size="small" tone="ink2">
            {label}
          </Sans>
        ) : (
          <Serif size="s" tone={tone}>
            {label}
          </Serif>
        )}
        {detail === undefined ? null : (
          <Mono className="mt-0.5 text-[10px]" numberOfLines={2}>
            {detail}
          </Mono>
        )}
      </View>
      {value === undefined ? null : (
        <Mono tone={valueTone} className="shrink text-right text-xs" numberOfLines={1}>
          {value}
        </Mono>
      )}
      {trailing}
      {pressable ? <View className="h-[7px] w-[7px] rotate-45 border-r-[1.5px] border-t-[1.5px] border-mute" /> : null}
    </Pressable>
  );
}
