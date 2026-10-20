import { Button, Mark, Mono, Sans, Screen, Serif } from "@vitals/ui";
import { useState } from "react";
import { Platform, View } from "react-native";

import { haptics } from "../../lib/haptics";
import { requestNotifications } from "../../notifications/alerts";
import { startAlertWatch } from "../../notifications/background";

const REASONS =
  Platform.OS === "web"
    ? ["Alarms show while this tab is open.", "You hear about a rule once, not on every check.", "Nothing leaves your tailnet. No push servers."]
    : ["Vitals checks your Mac in the background about every 15 minutes.", "You hear about a rule once, not on every check.", "Calm down works straight from the notification."];

function SampleAlert() {
  return (
    <View className="mx-[22px] gap-3 rounded-[22px] bg-sheet p-4" accessible accessibilityLabel="Example alert. Pressure high. Six agents are holding 2.2 gigabytes. Calm them?">
      <View className="flex-row items-start gap-3">
        <View className="h-9 w-9 items-center justify-center rounded-[9px] bg-bg">
          <Mark width={24} />
        </View>
        <View className="flex-1">
          <Sans size="small" weight="semibold">
            Pressure high
          </Sans>
          <Sans size="small" tone="ink2">
            Six agents are holding 2.2 GB. Calm them?
          </Sans>
        </View>
        <Mono className="text-[10px]">example</Mono>
      </View>
      <View className="border-t border-line2 pt-3">
        <Sans size="small" weight="medium">
          Calm down
        </Sans>
      </View>
    </View>
  );
}

export function AlertsScreen({ onDone }: { readonly onDone: () => void }) {
  const [asking, setAsking] = useState(false);

  const allow = () => {
    setAsking(true);
    void requestNotifications()
      .then(async (granted) => {
        if (!granted) return;
        haptics.success();
        await startAlertWatch();
      })
      .finally(onDone);
  };

  return (
    <Screen>
      <View className="gap-2 px-[22px] pb-6 pt-10">
        <Serif size="l" accessibilityRole="header">
          Let alarms reach you.
        </Serif>
        <Mono>Pressure Guard, from bed</Mono>
      </View>
      <SampleAlert />
      <View className="mt-6">
        {REASONS.map((reason, index) => (
          <View key={reason} className="flex-row gap-3 border-t border-line px-[22px] py-3.5">
            <Mono tone="pulse">{String(index + 1).padStart(2, "0")}</Mono>
            <Sans tone="ink2" className="flex-1">
              {reason}
            </Sans>
          </View>
        ))}
      </View>
      <View className="gap-3 px-[22px] pt-8">
        <Button label={asking ? "Asking" : "Allow alerts"} block disabled={asking} onPress={allow} />
        <Button label="Not now" variant="text" onPress={onDone} />
      </View>
    </Screen>
  );
}
