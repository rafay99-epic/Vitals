import type { BottomTabBarProps } from "@react-navigation/bottom-tabs";
import { haptics } from "@vitals/app/lib/haptics.ts";
import { useEffect, useState } from "react";
import { type LayoutChangeEvent, Pressable, StyleSheet, View } from "react-native";
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { Icon, type IconName } from "./Icon.tsx";
import { T } from "./Text.tsx";
import { color, curve, DOCK_BOTTOM, DOCK_HEIGHT, motion } from "./tokens.ts";

export interface DockTab {
  readonly label: string;
  readonly icon: IconName;
  /** A dot in this color on the icon: red for alerts, yellow for an update waiting. */
  readonly badge?: string | undefined;
}

const PAD = 6;

/** Floating tab bar. The yellow highlight slides between tabs; only transform animates. */
export function Dock({ state, navigation, tabs }: Pick<BottomTabBarProps, "state" | "navigation"> & { readonly tabs: Readonly<Record<string, DockTab>> }) {
  const insets = useSafeAreaInsets();
  const [width, setWidth] = useState(0);
  const offset = useSharedValue(0);
  const routes = state.routes.filter((route) => tabs[route.name] !== undefined);
  const slot = routes.length === 0 ? 0 : (width - PAD * 2) / routes.length;
  const active = routes.findIndex((route) => route.key === state.routes[state.index]?.key);

  useEffect(() => {
    offset.set(withTiming(Math.max(0, active) * slot, { duration: motion.dock, easing: curve.tray }));
  }, [active, slot, offset]);

  const indicator = useAnimatedStyle(() => ({ transform: [{ translateX: offset.get() }] }));

  return (
    <View
      accessibilityRole="tablist"
      onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)}
      style={[styles.dock, { bottom: insets.bottom + DOCK_BOTTOM }]}
    >
      {slot > 0 ? <Animated.View style={[styles.indicator, { width: slot }, indicator]} /> : null}
      {routes.map((route, index) => {
        const tab = tabs[route.name];
        if (tab === undefined) return null;
        const on = index === active;
        const press = () => {
          const event = navigation.emit({ type: "tabPress", target: route.key, canPreventDefault: true });
          if (on || event.defaultPrevented) return;
          haptics.select();
          navigation.navigate(route.name, route.params);
        };
        return (
          <Pressable
            key={route.key}
            onPress={press}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            accessibilityLabel={tab.badge === undefined ? tab.label : `${tab.label}, needs attention`}
            style={styles.tab}
          >
            <View>
              <Icon name={tab.icon} size={21} color={on ? color.yellow : color.mute} />
              {tab.badge === undefined ? null : <View style={[styles.badge, { backgroundColor: tab.badge }]} />}
            </View>
            <T v="tab" color={on ? color.yellow : color.mute}>
              {tab.label}
            </T>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  dock: {
    position: "absolute",
    left: 14,
    right: 14,
    height: DOCK_HEIGHT,
    borderRadius: DOCK_HEIGHT / 2,
    backgroundColor: "rgba(20,20,20,0.96)",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: color.line2,
    flexDirection: "row",
    paddingHorizontal: PAD,
    boxShadow: "0 10px 30px rgba(0,0,0,0.6)",
  },
  indicator: { position: "absolute", top: PAD, bottom: PAD, left: PAD, borderRadius: 25, backgroundColor: "rgba(242,236,107,0.13)" },
  tab: { flex: 1, alignItems: "center", justifyContent: "center", gap: 3 },
  badge: { position: "absolute", top: -2, right: -5, width: 9, height: 9, borderRadius: 5, borderWidth: 2, borderColor: "#141414" },
});
