import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";

export function Countdown({ title, deadline, onCancel }: { readonly title: string; readonly deadline: number; readonly onCancel: () => void }) {
  const remaining = useSharedValue(1);
  const [seconds, setSeconds] = useState<number | null>(null);

  useEffect(() => {
    const total = Math.max(deadline - Date.now(), 0);
    remaining.set(1);
    remaining.set(withTiming(0, { duration: total, easing: Easing.linear }));
    const update = () => setSeconds(Math.max(0, Math.ceil((deadline - Date.now()) / 1000)));
    const timer = setInterval(update, 250);
    const first = setTimeout(update, 0);
    const stop = setTimeout(() => clearInterval(timer), total + 300);
    return () => {
      clearInterval(timer);
      clearTimeout(first);
      clearTimeout(stop);
    };
  }, [deadline, remaining]);

  const bar = useAnimatedStyle(() => ({ width: `${remaining.get() * 100}%` }));

  return (
    <View className="mt-3 border border-bad">
      <Animated.View className="absolute inset-y-0 left-0 bg-bad/15" style={bar} />
      <View className="flex-row items-center justify-between px-4 py-3">
        <Text className="text-[15px] text-ink">{seconds === null ? title : `${title} in ${seconds}s`}</Text>
        <Pressable onPress={onCancel} accessibilityRole="button" hitSlop={10}>
          <Text className="text-[15px] font-semibold text-bad">Cancel</Text>
        </Pressable>
      </View>
    </View>
  );
}
