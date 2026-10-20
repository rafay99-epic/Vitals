import type { HistoryBucket } from "@vitals/contracts";
import { type Channel, EmptyState, HistoryChart, Mono, type Option, Segmented } from "@vitals/ui";
import { useEffect, useState } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { useStore } from "../../state/useStore.ts";
import { CHANNELS } from "./channels.ts";

type Range = "1h" | "24h" | "7d";

const RANGE_OPTIONS: ReadonlyArray<Option<Range>> = [
  { value: "1h", label: "1 h" },
  { value: "24h", label: "24 h" },
  { value: "7d", label: "7 d" },
];

const SPAN: Record<Range, number> = { "1h": 3_600_000, "24h": 86_400_000, "7d": 7 * 86_400_000 };

const QUARTERS = [0, 1, 2, 3];

const LABELS: Record<Range, (from: number) => ReadonlyArray<string>> = {
  "1h": () => ["-60m", "-45m", "-30m", "-15m", "now"],
  "24h": (from) => [...QUARTERS.map((quarter) => new Date(from + (quarter * SPAN["24h"]) / 4).toLocaleTimeString([], { hour: "numeric" })), "now"],
  "7d": (from) => [...QUARTERS.map((quarter) => new Date(from + (quarter * SPAN["7d"]) / 4).toLocaleDateString([], { weekday: "short" })), "now"],
};

const LOADING: Status = { _tag: "loading" };
const OFFLINE: Status = { _tag: "offline" };

interface Loaded {
  readonly buckets: ReadonlyArray<HistoryBucket>;
  readonly from: number;
  readonly to: number;
}

type Status = { readonly _tag: "loading" } | { readonly _tag: "offline" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly data: Loaded };

export function History({ channel }: { readonly channel: Channel }) {
  const remote = useRemote();
  const def = CHANNELS[channel];
  const ready = useStore(remote.connection.state)._tag === "Ready";
  const [range, setRange] = useState<Range>("1h");
  const [result, setResult] = useState<{ readonly range: Range; readonly status: Status } | null>(null);

  useEffect(() => {
    if (!ready) return;
    let cancelled = false;
    const to = Date.now();
    const from = to - SPAN[range];
    void remote.connection.call((client) => client["history.range"]({ series: [def.history], from, to, points: 120 })).then((outcome) => {
      if (cancelled) return;
      setResult({ range, status: outcome.ok ? { _tag: "loaded", data: { buckets: outcome.value.series[0]?.buckets ?? [], from, to } } : { _tag: "failed", message: outcome.error.message } });
    });
    return () => {
      cancelled = true;
    };
  }, [remote, ready, range, def.history]);

  const current = result !== null && result.range === range ? result.status : LOADING;
  const status = ready ? current : OFFLINE;

  return (
    <View className="pt-4">
      <Segmented options={RANGE_OPTIONS} value={range} onChange={setRange} />
      <HistoryBody channel={channel} status={status} range={range} />
    </View>
  );
}

function HistoryBody({ channel, status, range }: { readonly channel: Channel; readonly status: Status; readonly range: Range }) {
  const def = CHANNELS[channel];
  if (status._tag === "loading") return <Mono className="px-[22px] py-10">Loading history</Mono>;
  if (status._tag === "offline") return <EmptyState title="No signal." detail="History comes back with the Mac." />;
  if (status._tag === "failed") return <EmptyState title="History unavailable." detail={status.message} />;
  if (status.data.buckets.length === 0) return <EmptyState title="Nothing logged yet." detail="Vitals on the Mac records history while it runs." />;
  return (
    <View className="px-[22px] pt-4">
      <HistoryChart
        channel={channel}
        buckets={status.data.buckets}
        from={status.data.from}
        to={status.data.to}
        labels={LABELS[range](status.data.from)}
        format={def.historyFormat}
        floor={def.floor}
        ceiling={def.ceiling}
      />
    </View>
  );
}
