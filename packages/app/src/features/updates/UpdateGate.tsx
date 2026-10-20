import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { Button, channels, colors, Mark, Mono, Sans, Serif, type Tone } from "@vitals/ui";
import { useUpdates } from "expo-updates";
import { type ReactNode, useEffect, useState } from "react";
import { AppState, type LayoutChangeEvent, View } from "react-native";
import { Easing, useSharedValue, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { hideSplash } from "../../lib/splash.ts";
import { useStore } from "../../state/useStore.ts";
import { checkForUpdate, isBlocking, type UpdatePhase, updatePhase, updatesEnabled } from "./updateFlow.ts";

const TRACE_HEIGHT = 120;

type Step = "check" | "download" | "restart";

const STEPS: ReadonlyArray<{ readonly key: Step; readonly label: string }> = [
  { key: "check", label: "Check" },
  { key: "download", label: "Download" },
  { key: "restart", label: "Restart" },
];

interface Face {
  readonly word: string;
  readonly tone: Tone;
  readonly meta: string;
  readonly step: Step;
}

const face = (phase: UpdatePhase): Face => {
  switch (phase._tag) {
    case "Restarting":
      return { word: "Restarting.", tone: "pulse", meta: "the new version is in", step: "restart" };
    case "Failed":
      return { word: "Could not update.", tone: "alarmHigh", meta: phase.reason, step: "download" };
    case "Downloading":
      return { word: "Updating.", tone: "ink", meta: "downloading the new version", step: "download" };
    default:
      return { word: "Updating.", tone: "ink", meta: "looking for the new version", step: "check" };
  }
};

const beat = (width: number) =>
  Skia.PathBuilder.Make()
    .moveTo(0, 70)
    .lineTo(width * 0.28, 70)
    .lineTo(width * 0.32, 86)
    .lineTo(width * 0.38, 20)
    .lineTo(width * 0.43, 70)
    .lineTo(width, 70)
    .build();

function ProgressBeat({ progress }: { readonly progress: number }) {
  const [width, setWidth] = useState(0);
  const end = useSharedValue(0);
  useEffect(() => {
    end.set(withTiming(progress, { duration: 300, easing: Easing.out(Easing.cubic) }));
  }, [progress, end]);
  return (
    <View style={{ height: TRACE_HEIGHT }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      {width === 0 ? null : (
        <Canvas style={{ width, height: TRACE_HEIGHT }}>
          <Path path={beat(width)} style="stroke" strokeWidth={2.2} color={colors.line3} strokeJoin="round" />
          <Path path={beat(width)} style="stroke" strokeWidth={2.2} color={channels.pulse.color} start={0} end={end} strokeJoin="round" strokeCap="round" />
        </Canvas>
      )}
    </View>
  );
}

const ORDER: Record<Step, number> = { check: 0, download: 1, restart: 2 };

function Steps({ current }: { readonly current: Step }) {
  return (
    <View className="flex-row gap-4">
      {STEPS.map((step) => {
        const done = ORDER[step.key] < ORDER[current];
        const tone: Tone = step.key === current ? "ink" : "mute";
        return (
          <Mono key={step.key} tone={done ? "dim" : tone}>
            {done ? `✓ ${step.label}` : step.label}
          </Mono>
        );
      })}
    </View>
  );
}

const fraction = (phase: UpdatePhase, downloaded: number | undefined): number => {
  if (phase._tag === "Restarting") return 1;
  if (phase._tag === "Downloading") return Math.min(Math.max(downloaded ?? 0, 0), 1);
  return 0;
};

function Updating({ phase }: { readonly phase: UpdatePhase }) {
  const insets = useSafeAreaInsets();
  const { downloadProgress } = useUpdates();
  const look = face(phase);
  const progress = fraction(phase, downloadProgress);
  const percent = Math.round(progress * 100);
  return (
    <View className="flex-1 bg-bg px-[22px]" style={{ paddingTop: insets.top + 64, paddingBottom: insets.bottom + 32 }} accessibilityLiveRegion="polite">
      <View className="gap-2">
        <Serif size="state" italic tone={look.tone} accessibilityRole="header">
          {look.word}
        </Serif>
        <Mono tone={phase._tag === "Failed" ? "alarmHigh" : "dim"}>{look.meta}</Mono>
      </View>
      <View className="mt-10 gap-6">
        <ProgressBeat progress={progress} />
        <View className="flex-row items-baseline" accessible accessibilityLabel={`${String(percent)} percent`}>
          <Serif size="hero" tone={look.tone === "pulse" ? "pulse" : "ink"}>
            {String(percent)}
          </Serif>
          <Mono className="ml-1">%</Mono>
        </View>
        <Steps current={look.step} />
        {phase._tag === "Failed" ? <Button label="Try again" onPress={() => void checkForUpdate(true)} /> : null}
      </View>
      <Sans size="small" tone="dim" className="mt-auto">
        Vitals installs every update before it opens.
      </Sans>
    </View>
  );
}

function Quiet() {
  return (
    <View className="flex-1 items-center justify-center bg-bg">
      <Mark width={86} />
    </View>
  );
}

const screenFor = (phase: UpdatePhase, children: ReactNode): ReactNode => {
  if (phase._tag === "Checking" && phase.blocking) return <Quiet />;
  return isBlocking(phase) ? <Updating phase={phase} /> : children;
};

export function UpdateGate({ children }: { readonly children: ReactNode }) {
  const phase = useStore(updatePhase);
  const covered = phase._tag === "Checking" && phase.blocking;

  useEffect(() => {
    if (!covered) hideSplash();
  }, [covered]);

  useEffect(() => {
    if (!updatesEnabled) return;
    void checkForUpdate(true);
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") void checkForUpdate(false);
    });
    return () => subscription.remove();
  }, []);

  return screenFor(phase, children);
}
