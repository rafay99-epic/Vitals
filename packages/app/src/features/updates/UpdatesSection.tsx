import { formatDateTime } from "@vitals/shared";
import { Button, Row, Section } from "@vitals/ui";
import { View } from "react-native";

import { useStore } from "../../state/useStore.ts";
import { checkForUpdate, type UpdatePhase, updatePhase, updatesEnabled } from "./updateFlow.ts";
import { updateInfo } from "./updateInfo";

const lastCheck = (phase: UpdatePhase): string => {
  switch (phase._tag) {
    case "Idle":
      return updatesEnabled ? "not yet" : "off in this build";
    case "Checking":
      return "checking";
    case "Downloading":
      return "downloading";
    case "Restarting":
      return "restarting";
    case "Current":
      return `current · ${formatDateTime(phase.at)}`;
    case "Offline":
      return `unreachable · ${formatDateTime(phase.at)}`;
  }
};

const INFO = updateInfo();

export function UpdatesSection() {
  const phase = useStore(updatePhase);
  return (
    <Section title="Updates">
      <Row label="Channel" plain value={INFO.channel} />
      <Row label="Running" plain value={INFO.createdAt === null ? INFO.running : `${INFO.running} · ${formatDateTime(INFO.createdAt)}`} />
      <Row label="Runtime" plain value={INFO.runtime.slice(0, 12)} />
      <Row label="Last check" plain value={lastCheck(phase)} valueTone={phase._tag === "Offline" ? "alarmMedium" : "ink"} />
      <View className="border-t border-line px-[22px] py-3">
        <Button label="Check now" variant="line" small disabled={!updatesEnabled || phase._tag === "Checking"} onPress={() => void checkForUpdate(false)} />
      </View>
    </Section>
  );
}
