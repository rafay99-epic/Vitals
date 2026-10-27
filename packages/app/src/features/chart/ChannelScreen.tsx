import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { BackHeader, type Channel, channels, EmptyState, Mono, Screen, Serif, Trace } from "@vitals/ui";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import type { ChartStackParams } from "../../navigation/types.ts";
import { useStore } from "../../state/useStore.ts";
import { useSignal } from "../../state/useVitals.ts";
import { CHANNEL_DETAILS } from "./ChannelDetails.tsx";
import { CHANNELS, isChannel, titleOf } from "./channels.ts";
import { History } from "./History.tsx";
import { useLiveTopics } from "./hooks.ts";
import { LiveText } from "../../components/LiveText.tsx";

type Props = NativeStackScreenProps<ChartStackParams, "Channel">;

const NO_TOPICS = [] as const;

function ChannelBody({ channel }: { readonly channel: Channel }) {
  const remote = useRemote();
  const spec = channels[channel];
  const def = CHANNELS[channel];
  const signal = useSignal();
  const state = useStore(remote.connection.state);
  const memoryMax = state._tag === "Ready" ? (state.hello.mac?.memoryBytes ?? null) : null;
  const Details = CHANNEL_DETAILS[channel];
  return (
    <>
      <View className="px-[22px] pb-2 pt-1">
        <Serif size="state" italic tone={channel} accessibilityRole="header">
          {titleOf(channel)}
        </Serif>
        <Mono className="mt-1">{`${spec.label} · ${def.context}`}</Mono>
      </View>
      <View className="flex-row items-baseline gap-4 px-[22px] pb-2">
        <Serif size="xl2" tone={signal ? channel : "mute"}>
          <LiveText select={def.reading} />
        </Serif>
        {def.pair === undefined || !signal ? null : (
          <Mono tone="ink2">
            <LiveText select={def.pair.reading} />
            {` ${def.pair.label}`}
          </Mono>
        )}
      </View>
      <View className="border-y border-line px-[22px] py-3">
        <Trace channel={channel} source={remote.live.series(def.series)} pair={def.pair === undefined ? undefined : remote.live.series(def.pair.series)} height={80} min={def.min} max={channel === "press" ? memoryMax : def.max} beats={14} flat={!signal} />
      </View>
      <History channel={channel} />
      <View className="pt-6">
        <Details />
      </View>
    </>
  );
}

export function ChannelScreen({ navigation, route }: Props) {
  const channel = String(route.params.channel);
  useLiveTopics(isChannel(channel) ? CHANNELS[channel].topics : NO_TOPICS);
  const back = () => (navigation.canGoBack() ? navigation.goBack() : navigation.navigate("Chart"));
  return (
    <Screen>
      <BackHeader parent="Chart" onBack={back} />
      {isChannel(channel) ? <ChannelBody channel={channel} /> : <EmptyState title="No such channel." detail="Go back to the Chart and pick one of the vitals." />}
    </Screen>
  );
}
