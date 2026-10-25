import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { formatAmount } from "@vitals/app/features/clips/format.ts";
import type { Moving } from "@vitals/app/state/clips.ts";
import { fraction, type Progress } from "@vitals/app/state/transfer.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { StyleSheet, View } from "react-native";

import { Bar, color, Strip, T, Tap, toast } from "./ui/index.ts";

/** Text-only sends finish in one call, so they get no progress. */
const visible = (moving: Moving): boolean => moving.direction === "down" || moving.transfer.progress.get().total > 0;

const cancel = (moving: Moving) => {
  moving.transfer.cancel();
  toast.show(moving.direction === "up" ? "Stopped. Nothing was left on the Mac." : "Stopped. Nothing was saved.");
};

/** The Mac may clone or zip a file before the first chunk, which can take a while for big folders. */
const preparing = (moving: Moving, progress: Progress): boolean => moving.direction === "down" && progress.done === 0 && progress.phase === "running";

/** "3.1 of 7.9 MB", "Preparing on your Mac", or "Waiting for your Mac" while the connection is down. */
const amountLine = (moving: Moving, progress: Progress): string => {
  if (progress.phase === "waiting") return "Waiting for your Mac";
  if (preparing(moving, progress)) return "Preparing on your Mac";
  return formatAmount(progress.done, progress.total);
};

function MovingStrip({ moving }: { readonly moving: Moving }) {
  const progress = useStore(moving.transfer.progress);
  const tail =
    progress.phase === "waiting" ? "waiting for your Mac" : preparing(moving, progress) ? "preparing on your Mac" : `${String(Math.round(fraction(progress) * 100))}%`;
  return <Strip text={`${moving.transfer.label} · ${tail}`} action="Cancel" onAction={() => cancel(moving)} />;
}

/** Live progress above the dock for every download and upload, each with Cancel. */
export function TransferStrip() {
  const moving = useStore(useRemote().clips.moving);
  return moving.filter(visible).map((item) => <MovingStrip key={item.id} moving={item} />);
}

function Card({ moving }: { readonly moving: Moving }) {
  const progress = useStore(moving.transfer.progress);
  const state = useStore(useRemote().connection.state);
  const route = state._tag === "Ready" ? (state.route === "lan" ? "Wi-Fi" : "Tailscale") : null;
  const amount = amountLine(moving, progress);
  const live = route !== null && progress.phase === "running" && !preparing(moving, progress);
  return (
    <View style={styles.card}>
      <View style={styles.top}>
        <T v="strong" numberOfLines={1} style={styles.name}>
          {moving.transfer.label}
        </T>
        <Tap onPress={() => cancel(moving)} accessibilityRole="button" hitSlop={10}>
          <T v="strong" color={color.yellow}>
            Cancel
          </T>
        </Tap>
      </View>
      <T v="mono">{live ? `${amount} · ${route}` : amount}</T>
      <Bar value={fraction(progress)} />
    </View>
  );
}

/** The transfer card on the Clipboard screen: name, bytes so far, route, bar and Cancel. */
export function TransferCard() {
  const moving = useStore(useRemote().clips.moving).filter(visible);
  return moving.map((item) => <Card key={item.id} moving={item} />);
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, marginBottom: 12, backgroundColor: color.s2, borderRadius: 16, padding: 14, gap: 8 },
  top: { flexDirection: "row", alignItems: "center", gap: 12 },
  name: { flex: 1 },
});
