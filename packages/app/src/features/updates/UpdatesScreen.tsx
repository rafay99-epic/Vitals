import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { formatDateTime } from "@vitals/shared";
import { BackHeader, Button, KeyValueGrid, Mono, Row, Screen, Section, Serif } from "@vitals/ui";
import Constants from "expo-constants";
import { useEffect, useState } from "react";
import { View } from "react-native";

import { FirstBeat } from "../../components/FirstBeat.tsx";
import type { RecordStackParams } from "../../navigation/types.ts";
import { useStore } from "../../state/useStore.ts";
import { checkPlay, type PlayState, playState, playSupported, startPlayUpdate } from "./playUpdate";
import { checkForUpdate, type UpdatePhase, updatePhase, updatesEnabled } from "./updateFlow.ts";
import { updateInfo } from "./updateInfo";

type Props = NativeStackScreenProps<RecordStackParams, "Updates">;

const INFO = updateInfo();

const STATE: Record<UpdatePhase["_tag"], string> = {
  Idle: "updates are off in this build",
  Checking: "checking now",
  Downloading: "downloading",
  Restarting: "restarting",
  Current: "up to date",
  Offline: "could not reach the update server",
  Failed: "the last install failed",
};

const checkedAt = (phase: UpdatePhase): string => (phase._tag === "Current" || phase._tag === "Offline" || phase._tag === "Failed" ? ` · ${formatDateTime(phase.at)}` : "");

const playLine = (state: PlayState): string => {
  switch (state._tag) {
    case "Unchecked":
      return "not checked yet";
    case "Current":
      return "current";
    case "Available":
      return `version ${state.version} is out`;
    case "Downloading":
      return `downloading ${state.version}`;
    case "Unavailable":
      return state.reason;
  }
};

function Checking() {
  return (
    <View className="px-[22px] pt-4">
      <FirstBeat />
    </View>
  );
}

export function UpdatesScreen({ navigation }: Props) {
  const phase = useStore(updatePhase);
  const play = useStore(playState);
  const [round, setRound] = useState(0);
  const checking = phase._tag === "Checking";

  useEffect(() => {
    void checkPlay();
  }, []);

  const check = () => {
    setRound(round + 1);
    void checkForUpdate(false);
    void checkPlay();
  };

  return (
    <Screen
      top={
        <>
          <BackHeader parent="Record" onBack={() => navigation.goBack()} />
          <View className="gap-1 px-[22px] pb-3 pt-1">
            <Serif size="state" italic accessibilityRole="header">
              Updates.
            </Serif>
            <Mono>{`${STATE[phase._tag]}${checkedAt(phase)}`}</Mono>
          </View>
        </>
      }
    >
      <KeyValueGrid
        items={[
          { key: "This build", value: Constants.expoConfig?.version ?? "--" },
          { key: "Channel", value: INFO.channel },
          { key: "Running", value: INFO.running },
          { key: "Runtime", value: INFO.runtime.slice(0, 7) },
        ]}
      />
      <Section title="Over the air">
        <Row plain label="Published" value={INFO.createdAt === null ? "with this build" : formatDateTime(INFO.createdAt)} />
        <Row plain label="Launch" value={INFO.launchMs === null ? "--" : `${String(INFO.launchMs)} ms`} />
      </Section>
      {playSupported ? (
        <Section title="Google Play">
          <Row plain label="Store version" value={playLine(play)} valueTone={play._tag === "Available" ? "pulse" : "ink"} />
        </Section>
      ) : null}
      {checking ? <Checking key={round} /> : null}
      <View className="gap-3 px-[22px] pt-6">
        <Button label={checking ? "Checking" : "Check for updates"} block disabled={!updatesEnabled || checking} onPress={check} />
        {play._tag === "Available" ? <Button label="Update from Google Play" variant="line" block onPress={() => void startPlayUpdate()} /> : null}
      </View>
    </Screen>
  );
}
