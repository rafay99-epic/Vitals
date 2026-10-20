import type { ReactNode } from "react";
import { View } from "react-native";

import { Mono, Serif } from "../typography.tsx";

export function EmptyState({ title, detail, children }: { readonly title: string; readonly detail?: string | undefined; readonly children?: ReactNode }) {
  return (
    <View className="gap-3 px-[22px] py-10" accessible accessibilityLabel={detail === undefined ? title : `${title} ${detail}`}>
      <View className="h-px bg-line3" />
      <Serif size="m" italic>
        {title}
      </Serif>
      {detail === undefined ? null : <Mono className="leading-5">{detail}</Mono>}
      {children}
    </View>
  );
}
