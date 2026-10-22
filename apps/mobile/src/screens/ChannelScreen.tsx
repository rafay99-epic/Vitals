import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { CHANNEL_DETAILS } from "@vitals/app/features/chart/ChannelDetails.tsx";
import { CHANNELS } from "@vitals/app/features/chart/channels.ts";
import { History } from "@vitals/app/features/chart/History.tsx";
import { useLiveTopics } from "@vitals/app/features/chart/hooks.ts";
import { useLatest, useSignal } from "@vitals/app/state/useVitals.ts";
import { channels, Trace } from "@vitals/ui";
import { StyleSheet, View } from "react-native";

import { useMac } from "../lib/remote.ts";
import type { HomeStackParams } from "../navigation.ts";
import { BackBar, color, Page, T, Title } from "../ui/index.ts";

type Props = NativeStackScreenProps<HomeStackParams, "Channel">;

/** Detail for one reading: the live value, a larger trace, history, and the extra numbers. */
export function ChannelScreen({ route }: Props) {
  const channel = route.params.channel;
  const def = CHANNELS[channel];
  useLiveTopics(def.topics);
  const remote = useRemote();
  const reading = useLatest(def.reading);
  const signal = useSignal();
  const mac = useMac();
  const spec = channels[channel];
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
      </View>
      <T v="mono" style={styles.context}>
        {def.context}
      </T>
      <View style={styles.trace}>
        <Trace channel={channel} source={remote.live.series(def.series)} height={110} min={def.min} max={channel === "press" ? (mac?.memoryBytes ?? null) : def.max} beats={14} flat={!signal} />
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
  context: { paddingHorizontal: 20, paddingTop: 4, paddingBottom: 14 },
  trace: { paddingHorizontal: 20, paddingBottom: 6 },
  details: { paddingTop: 20 },
});
