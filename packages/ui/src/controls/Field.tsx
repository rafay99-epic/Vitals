import { useState } from "react";
import { TextInput, type TextInputProps, View } from "react-native";

import { colors } from "../theme.ts";
import { Mono, Tag } from "../typography.tsx";

export interface FieldProps extends Omit<TextInputProps, "className" | "style" | "placeholderTextColor"> {
  readonly label: string;
  readonly hint?: string | undefined;
  readonly error?: string | null | undefined;
  readonly mono?: boolean | undefined;
}

export const edgeClass = (error: string | null, focused: boolean): string => {
  if (error !== null) return "border-alarm-high";
  return focused ? "border-ink" : "border-line3";
};

export function Field({ label, hint, error = null, mono = false, multiline = false, ...input }: FieldProps) {
  const [focused, setFocused] = useState(false);
  const edge = edgeClass(error, focused);
  const face = mono ? "font-code text-sm" : "font-display text-m";
  return (
    <View className="gap-2 px-[22px] py-3">
      <Tag>{label}</Tag>
      <TextInput
        {...input}
        multiline={multiline}
        accessibilityLabel={label}
        placeholderTextColor={colors.mute}
        selectionColor={colors.ink}
        keyboardAppearance="dark"
        onFocus={(event) => {
          setFocused(true);
          input.onFocus?.(event);
        }}
        onBlur={(event) => {
          setFocused(false);
          input.onBlur?.(event);
        }}
        className={`text-ink ${edge} ${multiline ? "min-h-24 border p-3 font-text text-body" : `min-h-[52px] border-b px-0.5 ${face}`}`}
      />
      <FieldNote error={error} hint={hint} />
    </View>
  );
}

export function FieldNote({ error, hint }: { readonly error: string | null; readonly hint: string | undefined }) {
  if (error !== null) return <Mono tone="alarmHigh">{error}</Mono>;
  return hint === undefined ? null : <Mono>{hint}</Mono>;
}
