import { Pressable, Text, View } from "react-native";
import Animated, { cancelAnimation, runOnJS, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";

export function HoldButton({
  label,
  hint,
  onCommit,
  onStart,
  durationMs = 600,
  disabled = false,
}: {
  readonly label: string;
  readonly hint?: string;
  readonly onCommit: () => void;
  readonly onStart?: () => void;
  readonly durationMs?: number;
  readonly disabled?: boolean;
}) {
  const progress = useSharedValue(0);
  const fill = useAnimatedStyle(() => ({ width: `${progress.get() * 100}%` }));

  const begin = () => {
    onStart?.();
    progress.set(
      withTiming(1, { duration: durationMs }, (finished) => {
        if (finished) {
          progress.set(0);
          runOnJS(onCommit)();
        }
      }),
    );
  };

  const release = () => {
    cancelAnimation(progress);
    progress.set(withTiming(0, { duration: 120 }));
  };

  return (
    <Pressable
      onPressIn={begin}
      onPressOut={release}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityHint={hint ?? `Hold for ${durationMs} milliseconds`}
      className={`min-h-12 justify-center overflow-hidden border border-line ${disabled ? "opacity-40" : ""}`}
    >
      <Animated.View className="absolute inset-y-0 left-0 bg-line" style={fill} />
      <View className="flex-row items-center justify-between px-4">
        <Text className="text-[15px] font-medium text-ink">{label}</Text>
        <Text className="font-mono text-[11px] uppercase tracking-widest text-mute">hold</Text>
      </View>
    </Pressable>
  );
}
