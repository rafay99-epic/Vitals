import type { LiveSample } from "@vitals/contracts";
import { Text } from "react-native";

import { useLatest } from "../state/useVitals.ts";
import type { Reading } from "../state/vitals.ts";

export function LiveText({ select }: { readonly select: (sample: LiveSample | null) => Reading }) {
  const reading = useLatest(select);
  return (
    <Text>
      {reading.value}
      {reading.unit === "" ? null : <Text className="font-code text-[11px]">{` ${reading.unit}`}</Text>}
    </Text>
  );
}
