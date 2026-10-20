import { type ComponentRef, useRef, useState } from "react";
import { Pressable, TextInput, View } from "react-native";

import { colors } from "../theme.ts";
import { Serif, Tag } from "../typography.tsx";
import { edgeClass, FieldNote } from "./Field.tsx";

export interface CodeInputProps {
  readonly value: string;
  readonly length: number;
  readonly onChange: (value: string) => void;
  readonly onSubmit?: (() => void) | undefined;
  readonly error?: string | null | undefined;
  readonly hint?: string | undefined;
}

const GROUP = 4;

export function CodeInput({ value, length, onChange, onSubmit, error = null, hint }: CodeInputProps) {
  const input = useRef<ComponentRef<typeof TextInput>>(null);
  const [focused, setFocused] = useState(false);
  const groups = Array.from({ length: Math.ceil(length / GROUP) }, (_, index) => value.slice(index * GROUP, index * GROUP + GROUP));
  const cursor = Math.min(Math.floor(value.length / GROUP), groups.length - 1);
  return (
    <View className="gap-2 px-[22px] py-3">
      <Tag>Pairing code</Tag>
      <Pressable onPress={() => input.current?.focus()} accessibilityRole="none" className="flex-row gap-3">
        {groups.map((group, index) => (
          <View
            key={`group-${String(index)}`}
            className={`h-16 flex-1 items-center justify-center border-b ${edgeClass(error, focused && index === cursor)}`}
          >
            <Serif size="l" className="tracking-[4px]">
              {group.padEnd(GROUP, " ")}
            </Serif>
          </View>
        ))}
        <TextInput
          ref={input}
          value={value}
          onChangeText={onChange}
          onSubmitEditing={onSubmit}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          maxLength={length + 2}
          autoCapitalize="characters"
          autoCorrect={false}
          autoComplete="one-time-code"
          textContentType="oneTimeCode"
          keyboardAppearance="dark"
          accessibilityLabel="Pairing code"
          selectionColor={colors.ink}
          caretHidden
          className="absolute inset-0 text-transparent opacity-[0.02]"
        />
      </Pressable>
      <FieldNote error={error} hint={hint ?? `${String(value.length)} of ${String(length)}`} />
    </View>
  );
}
