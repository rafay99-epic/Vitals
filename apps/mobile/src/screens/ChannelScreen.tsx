import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { CHANNEL_DETAILS } from "@vitals/app/features/chart/ChannelDetails.tsx";
import { CHANNELS } from "@vitals/app/features/chart/channels.ts";
import { History } from "@vitals/app/features/chart/History.tsx";
import { useLiveTopics } from "@vitals/app/features/chart/hooks.ts";
import { useLatest, useSignal } from "@vitals/app/state/useVitals.ts";
import type { Reading } from "@vitals/app/state/vitals.ts";
import { type Channel, type ChannelSpec, channels, Trace } from "@vitals/ui";
import { StyleSheet, View } from "react-native";

import { useMac } from "../lib/remote.ts";
import type { HomeStackParams } from "../navigation.ts";
import { BackBar, color, Empty, Page, T, Title } from "../ui/index.ts";

type Props = NativeStackScreenProps<HomeStackParams, "Channel">;

const isChannel = (value: string): value is Channel => value in CHANNELS;

const NO_PAIR = (): Reading => ({ value: "", unit: "" });

/** Detail for one reading. The channel comes from a deep link too, so an unknown one gets a way back. */
export function ChannelScreen({ route }: Props) {
  const channel: string = route.params.channel;
  return isChannel(channel) ? (
    <ChannelDetail channel={channel} />
  ) : (
    <Page>
      <BackBar parent="Home" />
      <Empty title="Nothing here" detail="That reading does not exist." />
    </Page>
  );
}

/** The live value, a larger trace, history, and the extra numbers. */
function ChannelDetail({ channel }: { readonly channel: Channel }) {
  const def = CHANNELS[channel];
  useLiveTopics(def.topics);
  const remote = useRemote();
  const reading = useLatest(def.reading);
  const pair = useLatest(def.pair?.reading ?? NO_PAIR);
  const signal = useSignal();
  const mac = useMac();
  const spec: ChannelSpec = channels[channel];
  const Details = CHANNEL_DETAILS[channel];
  return (
    <Page>
      <BackBar parent="Home" />
      <Title>{`${spec.label}.`}</Title>
      <View style={styles.value}>
        <T v="hero" color={signal ? spec.color : color.mute}>
          {signal ? reading.value : "--"}
        </T>
        {signal && reading.unit !== "" ? (
          <T v="mono" style={styles.unit}>
            {reading.unit}
          </T>
        ) : null}
        {signal && def.pair !== undefined && pair.value !== "--" ? (
          <View style={styles.pair}>
            <T v="monoStrong" color={spec.pair}>{`${pair.value} ${pair.unit}`}</T>
            <T v="mono">{def.pair.label}</T>
          </View>
        ) : null}
      </View>
      <T v="mono" style={styles.context}>
        {def.context}
      </T>
      <View style={styles.trace}>
        <Trace channel={channel} source={remote.live.series(def.series)} pair={def.pair === undefined ? undefined : remote.live.series(def.pair.series)} height={110} min={def.min} max={channel === "press" ? (mac?.memoryBytes ?? null) : def.max} beats={14} flat={!signal} />
      </View>
      <History channel={channel} />
      <View style={styles.details}>
        <Details />
      </View>
    </Page>
  );
}

const styles = StyleSheet.create({
  value: { flexDirection: "row", alignItems: "baseline", gap: 6, paddingHorizontal: 20 },
  unit: { fontSize: 14 },
  pair: { marginLeft: 14 },
  context: { paddingHorizontal: 20, paddingTop: 4, paddingBottom: 14 },
  trace: { paddingHorizontal: 20, paddingBottom: 6 },
  details: { paddingTop: 20 },
});
