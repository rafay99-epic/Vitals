import type { ReactNode } from "react";
import { RefreshControl, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { colors } from "../theme.ts";

export interface ScreenProps {
  readonly children: ReactNode;
  readonly top?: ReactNode;
  readonly insetTop?: boolean | undefined;
  readonly refreshing?: boolean | undefined;
  readonly onRefresh?: (() => void) | undefined;
}

export function Screen({ children, top, insetTop = true, refreshing = false, onRefresh }: ScreenProps) {
  const insets = useSafeAreaInsets();
  return (
    <View className="flex-1 bg-bg" style={{ paddingTop: insetTop ? insets.top : 0 }}>
      {top}
      <ScrollView
        className="flex-1"
        contentContainerClassName="pb-16"
        keyboardShouldPersistTaps="handled"
        refreshControl={onRefresh === undefined ? undefined : <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.dim} colors={[colors.ink]} progressBackgroundColor={colors.sheet} />}
      >
        {children}
      </ScrollView>
    </View>
  );
}
