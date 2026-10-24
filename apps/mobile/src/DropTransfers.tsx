import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { type DropLive, dropLabel, isEnded, isIncoming, isOutgoing } from "@vitals/app/state/drops.ts";
import { useSelect } from "@vitals/app/state/useStore.ts";
import type { DeviceId, Drop, DropId } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { useCallback } from "react";
import { StyleSheet, View } from "react-native";

import { liveLine, percent } from "./lib/drops.ts";
import { askSheet } from "./sheets/FileSheets.tsx";
import { Bar, color, Icon, sheet, Strip, T, Tap, toast } from "./ui/index.ts";

const asking = (drop: Drop, me: DeviceId): boolean => drop.state === "asking" && isIncoming(drop, me);

const waitingLine = (drop: Drop, me: DeviceId): string | null => {
  if (drop.state === "paused") return "Paused on your Mac";
  if (drop.state === "asking") return "Waiting for your Mac to accept";
  if (drop.state === "waiting") return isOutgoing(drop, me) ? "Waiting for your Mac" : "Waiting";
  return null;
};

const titleOf = (drop: Drop, me: DeviceId): string => `${isIncoming(drop, me) ? "Getting" : "Sending"} ${dropLabel(drop)}`;

export const useMyDrops = (): ReadonlyArray<Drop> => {
  const remote = useRemote();
  const me = remote.credentials.deviceId;
  const mine = useCallback((drops: ReadonlyArray<Drop>) => drops.filter((drop) => !isEnded(drop) && (isIncoming(drop, me) || isOutgoing(drop, me))), [me]);
  return useSelect(remote.drops.drops, mine);
};

const useLive = (id: DropId): DropLive | null => {
  const remote = useRemote();
  const pick = useCallback((live: ReadonlyMap<DropId, DropLive>) => live.get(id) ?? null, [id]);
  return useSelect(remote.drops.live, pick);
};

const useCancel = (drop: Drop) => {
  const remote = useRemote();
  return () => void remote.drops.cancel(drop.id).then((ok) => ok && toast.show("Stopped"));
};

function Progress({ drop, me }: { readonly drop: Drop; readonly me: DeviceId }) {
  const live = useLive(drop.id);
  return (
    <>
      <T v="mono">{liveLine(live, waitingLine(drop, me))}</T>
      <Bar value={live === null || live.total === 0 ? 0 : live.done / live.total} />
    </>
  );
}

function AskCard({ drop }: { readonly drop: Drop }) {
  const remote = useRemote();
  return (
    <View style={styles.card}>
      <T v="strong">{`Your Mac wants to send ${dropLabel(drop)}`}</T>
      <T v="mono">{formatBytes(drop.bytes)}</T>
      <View style={styles.choices}>
        <Tap onPress={() => void remote.drops.accept(drop.id)} accessibilityRole="button" hitSlop={10}>
          <T v="strong" color={color.yellow}>
            Accept
          </T>
        </Tap>
        <Tap onPress={() => void remote.drops.decline(drop.id)} accessibilityRole="button" hitSlop={10}>
          <T v="strong" color={color.dim}>
            Decline
          </T>
        </Tap>
      </View>
    </View>
  );
}

function DropCard({ drop }: { readonly drop: Drop }) {
  const me = useRemote().credentials.deviceId;
  const cancel = useCancel(drop);
  if (asking(drop, me)) return <AskCard drop={drop} />;
  return (
    <View style={styles.card}>
      <View style={styles.top}>
        <T v="strong" numberOfLines={1} style={styles.grow}>
          {titleOf(drop, me)}
        </T>
        <Tap onPress={cancel} accessibilityRole="button" hitSlop={10}>
          <T v="strong" color={color.dim}>
            Cancel
          </T>
        </Tap>
      </View>
      <Progress drop={drop} me={me} />
    </View>
  );
}

export function DropCards() {
  return useMyDrops().map((drop) => <DropCard key={drop.id} drop={drop} />);
}

function DropStrip({ drop, me }: { readonly drop: Drop; readonly me: DeviceId }) {
  const live = useLive(drop.id);
  const cancel = useCancel(drop);
  const waiting = waitingLine(drop, me);
  const where = isIncoming(drop, me) ? " from your Mac" : "";
  return <Strip text={`${titleOf(drop, me)}${where} · ${waiting === null ? percent(live) : waiting.toLowerCase()}`} action="Cancel" onAction={cancel} />;
}

export function DropStrips() {
  const me = useRemote().credentials.deviceId;
  return useMyDrops()
    .filter((drop) => !asking(drop, me))
    .map((drop) => <DropStrip key={drop.id} drop={drop} me={me} />);
}

function IncomingRow({ drop, me, onOpen }: { readonly drop: Drop; readonly me: DeviceId; readonly onOpen: () => void }) {
  const live = useLive(drop.id);
  const ask = asking(drop, me);
  const title = ask ? `Your Mac wants to send ${dropLabel(drop)}` : `Getting ${dropLabel(drop)} from your Mac · ${percent(live)}`;
  return (
    <Tap onPress={ask ? () => sheet.open(askSheet(drop)) : onOpen} accessibilityRole="button" accessibilityLabel={title} scale={0.99} style={styles.incoming}>
      <View style={styles.tile}>
        <Icon name="down" size={16} color={color.blue} />
      </View>
      <View style={styles.grow}>
        <T v="medium" numberOfLines={1}>
          {title}
        </T>
        {ask ? <T v="small">{`${formatBytes(drop.bytes)} · Tap to accept`}</T> : <Progress drop={drop} me={me} />}
      </View>
    </Tap>
  );
}

export function IncomingLines({ onOpen }: { readonly onOpen: () => void }) {
  const me = useRemote().credentials.deviceId;
  return useMyDrops()
    .filter((drop) => isIncoming(drop, me))
    .map((drop) => <IncomingRow key={drop.id} drop={drop} me={me} onOpen={onOpen} />);
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, marginBottom: 10, backgroundColor: color.s2, borderRadius: 16, padding: 14, gap: 8 },
  top: { flexDirection: "row", alignItems: "center", gap: 12 },
  grow: { flex: 1, gap: 4 },
  choices: { flexDirection: "row", gap: 22, paddingTop: 2 },
  incoming: { flexDirection: "row", alignItems: "center", gap: 12, marginHorizontal: 16, marginBottom: 10, backgroundColor: color.s2, borderRadius: 16, paddingHorizontal: 14, paddingVertical: 11 },
  tile: { width: 34, height: 34, borderRadius: 10, backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
});
