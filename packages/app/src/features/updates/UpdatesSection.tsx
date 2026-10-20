import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Row, Section } from "@vitals/ui";

import type { RecordStackParams } from "../../navigation/types.ts";
import { useStore } from "../../state/useStore.ts";
import { playState } from "./playUpdate";
import { type UpdatePhase, updatePhase } from "./updateFlow.ts";
import { updateInfo } from "./updateInfo";

const INFO = updateInfo();

const SUMMARY: Record<UpdatePhase["_tag"], string> = {
  Idle: "off in this build",
  Checking: "checking",
  Downloading: "downloading",
  Restarting: "restarting",
  Current: "up to date",
  Offline: "unreachable",
  Failed: "install failed",
};

export function UpdatesSection() {
  const navigation = useNavigation<NativeStackNavigationProp<RecordStackParams>>();
  const phase = useStore(updatePhase);
  const store = useStore(playState);
  const storeNews = store._tag === "Available";
  return (
    <Section title="Updates">
      <Row
        label="Updates"
        detail={`${INFO.channel} channel · ${INFO.running}`}
        value={storeNews ? "Google Play update" : SUMMARY[phase._tag]}
        valueTone={storeNews || phase._tag === "Offline" ? "alarmMedium" : "ink"}
        onPress={() => navigation.navigate("Updates")}
      />
    </Section>
  );
}
