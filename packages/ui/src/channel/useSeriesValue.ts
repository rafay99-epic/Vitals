import { useEffect } from "react";
import { type SharedValue, useSharedValue } from "react-native-reanimated";

import type { SeriesSource } from "../series.ts";

export const useSeriesValue = (source: SeriesSource): SharedValue<ReadonlyArray<number>> => {
  const points = useSharedValue<ReadonlyArray<number>>(source.values());
  useEffect(() => {
    points.set(source.values());
    return source.subscribe(() => points.set(source.values()));
  }, [source, points]);
  return points;
};
