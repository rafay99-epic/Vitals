import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import type { KeepAwakeState, LiveSample, MacInfo } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { type Channel, CHANNEL_ORDER, ChannelRow, channels, Screen, useWide } from "@vitals/ui";
import { Text } from "react-native";

import { TabHeader } from "../../components/TabHeader.tsx";
import { useRemote } from "../../connection/useRemote.ts";
import type { ChartStackParams } from "../../navigation/types.ts";
import { useStore } from "../../state/useStore.ts";
import { useLatest, useSignal } from "../../state/useVitals.ts";
import { ChartBanners } from "./ChartBanners.tsx";
import { CHANNELS, CHART_COMPACT, CHART_FULL, LIVE_STATE, LIVE_TOPICS, rowState } from "./channels.ts";
import { EventStrip } from "./EventStrip.tsx";
import { useLiveTopics } from "./hooks.ts";
import { isBroken, LinkState } from "./LinkState.tsx";
import { LiveText } from "../../components/LiveText.tsx";

type Props = NativeStackScreenProps<ChartStackParams, "Chart">;

type RowSize = "full" | "compact" | "lane";

const keepAwakeText = (state: KeepAwakeState): string => (state.until === null ? "keeping awake" : `keeping awake · until ${formatClock(state.until)}`);

function ChartMeta({ mac }: { readonly mac: MacInfo | null }) {
  const keepAwake = useStore(useRemote().events.keepAwake);
  if (keepAwake?.active === true) return <Text className="text-alarm-medium">{keepAwakeText(keepAwake)}</Text>;
  return <Text>{mac === null ? "waiting for the Mac" : `${mac.chip} · ${mac.os}`}</Text>;
}

const RULES = new Map(CHANNEL_ORDER.map((key) => [key, new Set(CHANNELS[key].rules)]));

function LiveChannel({ channel, size, memoryMax, order, onOpen }: { readonly channel: Channel; readonly size: RowSize; readonly memoryMax: number | null; readonly order: number; readonly onOpen: (channel: Channel) => void }) {
  const remote = useRemote();
  const def = CHANNELS[channel];
  const signal = useSignal();
  const alarmed = useStore(remote.events.alerts).some((alert) => RULES.get(channel)?.has(alert.rule) === true);
  const live = useLatest(LIVE_STATE[channel]);
  const label = channels[channel].label;
  return (
    <ChannelRow
      channel={channel}
      source={remote.live.series(def.series)}
      value={<LiveText select={def.reading} />}
      min={def.min}
      max={channel === "press" ? memoryMax : def.max}
      state={rowState(live, alarmed, signal)}
      size={size}
      order={order}
      onPress={() => onOpen(channel)}
      accessibilityHint={`Opens the ${label} chart.`}
    />
  );
}

type Hardware = "both" | "fans" | "battery" | "neither";

const HARDWARE: Record<Hardware, ReadonlySet<Channel>> = {
  both: new Set(),
  fans: new Set(["oxy"]),
  battery: new Set(["resp"]),
  neither: new Set(["oxy", "resp"]),
};

const hardware = (fansHint: boolean, batteryHint: boolean) => (sample: LiveSample | null): Hardware => {
  const fans = sample?.fans === undefined ? fansHint : sample.fans.length > 0;
  const battery = sample?.battery === undefined ? batteryHint : sample.battery !== null;
  if (fans && battery) return "both";
  if (fans) return "fans";
  return battery ? "battery" : "neither";
};

type Hint = `${boolean}-${boolean}`;

const HARDWARE_OF: Record<Hint, (sample: LiveSample | null) => Hardware> = {
  "true-true": hardware(true, true),
  "true-false": hardware(true, false),
  "false-true": hardware(false, true),
  "false-false": hardware(false, false),
};

const hintOf = (mac: MacInfo | null): Hint => `${mac?.hasFans !== false}-${mac?.hasBattery !== false}`;

export function ChartScreen({ navigation }: Props) {
  useLiveTopics(LIVE_TOPICS);
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const wide = useWide();
  const mac = state._tag === "Ready" ? state.hello.mac : null;
  const missing = HARDWARE[useLatest(HARDWARE_OF[hintOf(mac)])];
  if (isBroken(state)) return <LinkState state={state} who={mac?.name ?? "Your Mac"} />;
  const shown = (channel: Channel) => !missing.has(channel);
  const memoryMax = mac?.memoryBytes ?? null;
  const open = (channel: Channel) => navigation.navigate("Channel", { channel });
  const row = (size: RowSize) => (channel: Channel, order: number) => <LiveChannel key={channel} channel={channel} size={size} memoryMax={memoryMax} order={order} onOpen={open} />;
  const rows = wide
    ? [...CHART_FULL, ...CHART_COMPACT].filter(shown).map(row("lane"))
    : [...CHART_FULL.filter(shown).map(row("full")), ...CHART_COMPACT.map((channel, index) => row("compact")(channel, index + CHART_FULL.length))];
  return (
    <Screen top={<ChartBanners />}>
      <TabHeader meta={<ChartMeta mac={mac} />} />
      {rows}
      {wide ? <EventStrip /> : null}
    </Screen>
  );
}
