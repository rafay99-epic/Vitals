import { formatDateTime } from "@vitals/shared";
import { Button, Mark, Mono, Sans, Serif } from "@vitals/ui";
import { type ReactNode, useEffect } from "react";
import { AppState, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { useStore } from "../../state/useStore.ts";
import { checkForUpdate, isBlocking, type UpdatePhase, updatePhase, updatesEnabled } from "./updateFlow.ts";

const STEPS = ["Checking", "Downloading", "Restarting"] as const;

const published = (phase: UpdatePhase): string | null =>
  (phase._tag === "Downloading" || phase._tag === "Restarting") && phase.publishedAt !== null ? `Published ${formatDateTime(phase.publishedAt)}` : null;

const TITLE: Partial<Record<UpdatePhase["_tag"], string>> = { Checking: "Checking.", Failed: "Could not update." };

function Updating({ phase }: { readonly phase: UpdatePhase }) {
  const insets = useSafeAreaInsets();
  const note = published(phase);
  return (
    <View className="flex-1 justify-between bg-bg px-[22px]" style={{ paddingTop: insets.top + 24, paddingBottom: insets.bottom + 32 }} accessibilityLiveRegion="polite">
      <Mark width={42} />
      <View className="gap-4">
        <Serif size="state" italic accessibilityRole="header">
          {TITLE[phase._tag] ?? "Updating."}
        </Serif>
        <View className="flex-row gap-4">
          {STEPS.map((name) => (
            <Mono key={name} tone={phase._tag === name ? "ink" : "mute"}>
              {name}
            </Mono>
          ))}
        </View>
        {note === null ? null : <Mono>{note}</Mono>}
        {phase._tag === "Failed" ? <FailedNote reason={phase.reason} /> : null}
      </View>
      <Sans size="small" tone="dim">
        Vitals installs every update before it opens.
      </Sans>
    </View>
  );
}

function FailedNote({ reason }: { readonly reason: string }) {
  return (
    <View className="gap-4">
      <Mono tone="alarmHigh">{reason}</Mono>
      <Button label="Try again" onPress={() => void checkForUpdate(true)} />
    </View>
  );
}

export function UpdateGate({ children }: { readonly children: ReactNode }) {
  const phase = useStore(updatePhase);

  useEffect(() => {
    if (!updatesEnabled) return;
    void checkForUpdate(true);
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") void checkForUpdate(false);
    });
    return () => subscription.remove();
  }, []);

  return isBlocking(phase) ? <Updating phase={phase} /> : children;
}
