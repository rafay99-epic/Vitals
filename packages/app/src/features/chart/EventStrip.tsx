import { formatClock } from "@vitals/shared";
import { Mono, Tag } from "@vitals/ui";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { useStore } from "../../state/useStore.ts";
import { orderLabel } from "../../state/commands.ts";

const KEPT = 6;

interface Entry {
  readonly id: string;
  readonly at: number;
  readonly text: string;
  readonly alarm: boolean;
}

export function EventStrip() {
  const remote = useRemote();
  const receipts = useStore(remote.events.receipts);
  const alerts = useStore(remote.events.alerts);
  const entries: Array<Entry> = [
    ...alerts.map((alert) => ({ id: alert.id, at: alert.raisedAt, text: `alarm · ${alert.summary}`, alarm: true })),
    ...receipts.map((receipt) => ({ id: receipt.id, at: receipt.finishedAt ?? receipt.createdAt, text: `${orderLabel(receipt.kind).toLowerCase()} · ${receipt.status}`, alarm: false })),
  ];
  const recent = entries.sort((a, b) => b.at - a.at).slice(0, KEPT);
  return (
    <View className="flex-row flex-wrap items-center gap-x-7 gap-y-2 border-t border-line px-8 py-4">
      <Tag>Log</Tag>
      {recent.length === 0 ? <Mono>Nothing yet this session.</Mono> : null}
      {recent.map((entry) => (
        <Mono key={entry.id} tone={entry.alarm ? "alarmHigh" : "dim"}>
          {`${formatClock(entry.at)} ${entry.text}`}
        </Mono>
      ))}
    </View>
  );
}
