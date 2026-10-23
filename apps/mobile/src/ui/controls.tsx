import { haptics } from "@vitals/app/lib/haptics.ts";
import { useEffect, useState } from "react";
import { type LayoutChangeEvent, Pressable, StyleSheet, TextInput, type TextInputProps, View } from "react-native";
import Animated, { interpolateColor, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";

import { Icon } from "./Icon.tsx";
import { T } from "./Text.tsx";
import { Tap } from "./Tap.tsx";
import { color, curve, font, motion } from "./tokens.ts";

/** On/off switch. The thumb slides; the track fades to yellow. */
export function Toggle({ value, onChange, label, disabled = false }: { readonly value: boolean; readonly onChange: (next: boolean) => void; readonly label: string; readonly disabled?: boolean }) {
  const on = useSharedValue(value ? 1 : 0);
  useEffect(() => {
    on.set(withTiming(value ? 1 : 0, { duration: motion.toggle, easing: curve.tray }));
  }, [value, on]);
  const track = useAnimatedStyle(() => ({ backgroundColor: interpolateColor(on.get(), [0, 1], ["#333333", color.yellow]) }));
  const thumb = useAnimatedStyle(() => ({
    transform: [{ translateX: on.get() * 18 }],
    backgroundColor: interpolateColor(on.get(), [0, 1], ["#bbbbbb", color.bg]),
  }));
  return (
    <Pressable
      onPress={() => {
        haptics.light();
        onChange(!value);
      }}
      disabled={disabled}
      hitSlop={8}
      accessibilityRole="switch"
      accessibilityLabel={label}
      accessibilityState={{ checked: value, disabled }}
      style={disabled ? styles.off : null}
    >
      <Animated.View style={[styles.track, track]}>
        <Animated.View style={[styles.thumb, thumb]} />
      </Animated.View>
    </Pressable>
  );
}

export interface SegmentOption<V extends string> {
  readonly value: V;
  readonly label: string;
}

/** Segmented choice with a sliding yellow indicator. */
export function Segmented<V extends string>({
  options,
  value,
  onChange,
  disabled = false,
}: {
  readonly options: ReadonlyArray<SegmentOption<V>>;
  readonly value: V | null;
  readonly onChange: (next: V) => void;
  readonly disabled?: boolean;
}) {
  const [width, setWidth] = useState(0);
  const slot = options.length === 0 ? 0 : (width - 8) / options.length;
  const index = options.findIndex((option) => option.value === value);
  const offset = useSharedValue(0);
  useEffect(() => {
    offset.set(withTiming(Math.max(0, index) * slot, { duration: motion.segment, easing: curve.tray }));
  }, [index, slot, offset]);
  const indicator = useAnimatedStyle(() => ({ transform: [{ translateX: offset.get() }] }));
  return (
    <View style={[styles.segment, disabled ? styles.off : null]} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)} accessibilityRole="radiogroup">
      {slot > 0 && index >= 0 ? <Animated.View style={[styles.segmentIndicator, { width: slot }, indicator]} /> : null}
      {options.map((option) => {
        const on = option.value === value;
        return (
          <Pressable
            key={option.value}
            disabled={disabled}
            onPress={() => {
              haptics.select();
              onChange(option.value);
            }}
            accessibilityRole="radio"
            accessibilityState={{ checked: on, disabled }}
            style={styles.segmentItem}
          >
            <T v="strong" color={on ? color.bg : color.dim}>
              {option.label}
            </T>
          </Pressable>
        );
      })}
    </View>
  );
}

/** Filter chip with an optional count. */
export function Chip({ label, count, on, onPress }: { readonly label: string; readonly count?: number | undefined; readonly on: boolean; readonly onPress: () => void }) {
  return (
    <Tap onPress={onPress} accessibilityRole="button" accessibilityState={{ selected: on }} style={[styles.chip, on ? styles.chipOn : null]}>
      <T v="medium" color={on ? color.bg : color.ink2} style={styles.chipText}>
        {label}
      </T>
      {count === undefined ? null : (
        <T v="mono" color={on ? color.bg : color.dim}>
          {String(count)}
        </T>
      )}
    </Tap>
  );
}

/** Search input with a leading icon. */
export function SearchField(props: Omit<TextInputProps, "style">) {
  return (
    <View style={styles.search}>
      <Icon name="search" size={15} color={color.mute} />
      <TextInput
        placeholderTextColor={color.mute}
        autoCapitalize="none"
        autoCorrect={false}
        returnKeyType="search"
        clearButtonMode="while-editing"
        selectionColor={color.yellow}
        {...props}
        style={styles.searchInput}
      />
    </View>
  );
}

/** Plain text field used inside sheets. */
export function Field(props: Omit<TextInputProps, "style"> & { readonly tall?: boolean }) {
  const { tall = false, ...rest } = props;
  return (
    <TextInput
      placeholderTextColor={color.mute}
      selectionColor={color.yellow}
      {...rest}
      multiline={tall}
      style={[styles.field, tall ? styles.tall : null]}
    />
  );
}

const styles = StyleSheet.create({
  off: { opacity: 0.4 },
  track: { width: 44, height: 26, borderRadius: 13, justifyContent: "center", paddingHorizontal: 3 },
  thumb: { width: 20, height: 20, borderRadius: 10 },
  segment: { flexDirection: "row", marginHorizontal: 16, marginBottom: 14, backgroundColor: color.s2, borderRadius: 14, padding: 4 },
  segmentIndicator: { position: "absolute", top: 4, bottom: 4, left: 4, borderRadius: 10, backgroundColor: color.yellow },
  segmentItem: { flex: 1, alignItems: "center", paddingVertical: 9 },
  chip: { flexDirection: "row", alignItems: "center", gap: 6, backgroundColor: color.s2, borderRadius: 18, paddingHorizontal: 12, paddingVertical: 7 },
  chipOn: { backgroundColor: color.yellow },
  chipText: { fontSize: 12.5 },
  search: { flexDirection: "row", alignItems: "center", gap: 9, marginHorizontal: 16, marginBottom: 12, backgroundColor: color.s2, borderRadius: 14, paddingHorizontal: 13 },
  searchInput: { flex: 1, paddingVertical: 12, fontFamily: font.sans, fontSize: 14, color: color.ink },
  field: {
    marginHorizontal: 16,
    marginBottom: 10,
    backgroundColor: color.bg,
    borderWidth: 1,
    borderColor: color.line2,
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontFamily: font.sans,
    fontSize: 14,
    color: color.ink,
  },
  tall: { minHeight: 90, textAlignVertical: "top" },
});
