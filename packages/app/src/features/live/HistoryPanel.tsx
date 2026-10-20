import type { HistoryBucket, HistorySeries } from "@vitals/contracts";
import { BandChart, Section, Segmented, colors } from "@vitals/ui";
import { useEffect, useState } from "react";
import { Text, View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { useStore } from "../../state/useStore.ts";

type Range = "1h" | "24h" | "7d";

const SPANS: Record<Range, number> = { "1h": 3_600_000, "24h": 86_400_000, "7d": 7 * 86_400_000 };

export function HistoryPanel({
  series,
  format,
  floor = 0,
  ceiling,
  color = colors.accent,
}: {
  readonly series: HistorySeries;
  readonly format: (value: number) => string;
  readonly floor?: number;
  readonly ceiling?: number;
  readonly color?: string;
}) {
  const remote = useRemote();
  const ready = useStore(remote.connection.state)._tag === "Ready";
  const [range, setRange] = useState<Range>("1h");
  const [data, setData] = useState<{ readonly buckets: ReadonlyArray<HistoryBucket>; readonly from: number; readonly to: number } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!ready) return;
    let cancelled = false;
    const to = Date.now();
    const from = to - SPANS[range];
    void remote.connection
      .call((client) => client["history.range"]({ series: [series], from, to, points: 120 }))
      .then((result) => {
        if (cancelled) return;
        if (result.ok) {
          setData({ buckets: result.value.series[0]?.buckets ?? [], from, to });
          setError(null);
        } else {
          setError(result.error.message);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [remote, ready, range, series]);

  return (
    <Section
      title="History"
      trailing={
        <View className="w-36">
        <Segmented
          options={[
            { value: "1h", label: "1H" },
            { value: "24h", label: "24H" },
            { value: "7d", label: "7D" },
          ]}
          value={range}
          onChange={setRange}
        />
        </View>
      }
    >
      {error !== null ? (
        <Text className="text-sm text-warn">{error}</Text>
      ) : data === null ? (
        <Text className="text-sm text-mute">Loading</Text>
      ) : (
        <BandChart
          buckets={data.buckets}
          from={data.from}
          to={data.to}
          format={format}
          floor={floor}
          color={color}
          {...(ceiling === undefined ? {} : { ceiling })}
        />
      )}
    </Section>
  );
}
