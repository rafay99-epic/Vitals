import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { formatClock, formatDateTime } from "@vitals/shared";
import { BackHeader, Button, EmptyState, KeyValueGrid, Row, Screen, Section, Spark } from "@vitals/ui";
import Constants from "expo-constants";
import { Share, View } from "react-native";

import { TabHeader } from "../../components/TabHeader.tsx";
import { isStoreBuild } from "../../lib/variant";
import type { RecordStackParams } from "../../navigation/types.ts";
import { diagnostics, type MethodStats, throwTestError } from "../../state/diagnostics.ts";
import { useLink, useNow } from "../../state/useVitals.ts";
import { bytes, fixed } from "../../state/vitals.ts";
import { updateInfo } from "../updates/updateInfo";
import { useFrameRate } from "./useFrameRate.ts";

type Props = NativeStackScreenProps<RecordStackParams, "Diagnostics">;

const INFO = updateInfo();
const SPARK = { width: 96, height: 24 } as const;

const median = (values: ReadonlyArray<number>): number => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)] ?? Number.NaN;
};

const ms = (value: number | null): string => (value === null || !Number.isFinite(value) ? "--" : value.toFixed(0));

const ago = (value: number | null): { readonly value: string; readonly unit: string } =>
  value !== null && value >= 10_000 ? { value: (value / 1000).toFixed(0), unit: "s ago" } : { value: ms(value), unit: "ms ago" };

const uptime = (now: number): string => {
  const minutes = Math.floor((now - diagnostics.startedAt) / 60_000);
  return minutes < 60 ? `${String(minutes)} min` : `${String(Math.floor(minutes / 60))} h ${String(minutes % 60)} min`;
};

function CallRow({ stats }: { readonly stats: MethodStats }) {
  return (
    <Row
      label={stats.method}
      detail={`${String(stats.calls)} calls · ${String(stats.failures)} failed · p50 ${ms(stats.p50Ms)} ms · p95 ${ms(stats.p95Ms)} ms`}
      trailing={<Spark channel="drip" values={stats.recent} width={SPARK.width} height={SPARK.height} />}
    />
  );
}

function Link() {
  const link = useLink();
  return <Row label="State" plain value={link.label} />;
}

export function DiagnosticsScreen({ navigation }: Props) {
  if (!isStoreBuild) return <Diagnostics onBack={() => navigation.goBack()} />;
  return (
    <Screen top={<BackHeader parent="Record" onBack={() => navigation.goBack()} />}>
      <EmptyState title="Diagnostics are in the dev build." />
    </Screen>
  );
}

/** The dev-build diagnostics view, usable from any navigator. */
export function Diagnostics({ onBack, parent = "Record" }: { readonly onBack: () => void; readonly parent?: string }) {
  const now = useNow(1000);
  useFrameRate();

  const intervals = diagnostics.intervals.toArray();
  const frames = diagnostics.frames.toArray();
  const heap = diagnostics.heap();
  const heapBytes = bytes(heap?.heapBytes);
  const allocated = bytes(heap?.allocatedBytes);
  const calls = diagnostics.methodStats();
  const appVersion = Constants.expoConfig?.version ?? "unknown";

  const share = () =>
    void Share.share({
      title: "Vitals diagnostics",
      message: diagnostics.report({ appVersion, update: INFO }),
    });

  return (
    <Screen
      top={
        <>
          <BackHeader parent={parent} onBack={onBack} />
          <TabHeader title="Diagnostics." meta={`dev build · up ${uptime(now)} · kept in memory only`} />
        </>
      }
    >
      <Section title="Link">
        <Link />
        <KeyValueGrid
          items={[
            { key: "Samples", value: String(diagnostics.samples) },
            { key: "Reconnects", value: String(diagnostics.reconnects), tone: diagnostics.reconnects > 0 ? "alarmMedium" : "ink" },
            { key: "Last sample", ...ago(diagnostics.lastSampleAge(now)) },
            { key: "Interval p50", value: ms(median(intervals)), unit: "ms" },
            { key: "Interval max", value: ms(intervals.length === 0 ? null : Math.max(...intervals)), unit: "ms" },
            { key: "Drift", value: ms(intervals.length === 0 ? null : Math.max(...intervals) - Math.min(...intervals)), unit: "ms" },
          ]}
        />
        <Row label="Sample intervals" plain trailing={<Spark channel="tele" values={intervals} width={SPARK.width} height={SPARK.height} />} />
      </Section>

      <Section title="Frames and memory">
        <KeyValueGrid
          items={[
            { key: "Frame rate", value: fixed(frames.at(-1)), unit: "fps" },
            { key: "Lowest", value: frames.length === 0 ? "--" : String(Math.min(...frames)), unit: "fps" },
            { key: "JS heap", value: heapBytes.value, unit: heapBytes.unit },
            { key: "Allocated", value: allocated.value, unit: allocated.unit },
          ]}
        />
        <Row label="Frame rate, last minute" plain trailing={<Spark channel="pulse" values={frames} width={SPARK.width} height={SPARK.height} max={120} />} />
      </Section>

      <Section title="Calls" trailing={`${String(calls.length)} methods`}>
        {calls.length === 0 ? <EmptyState title="No calls yet." /> : calls.map((stats) => <CallRow key={stats.method} stats={stats} />)}
      </Section>

      <Section title="Timeline" trailing={`${String(diagnostics.transitions.length)} changes`}>
        {diagnostics.transitions.map((item) => (
          <Row key={`${String(item.at)}-${item.to}`} label={item.to} plain detail={item.detail === "" ? `from ${item.from}` : `from ${item.from} · ${item.detail}`} value={formatClock(item.at)} />
        ))}
      </Section>

      <Section title="Faults">
        <Row label="Throw a test error" detail="Checks errors reach your Mac and Sentry" onPress={throwTestError} />
        {diagnostics.faults.length === 0 ? (
          <EmptyState title="No faults." detail="Uncaught errors land here with the time they happened." />
        ) : (
          diagnostics.faults.map((fault) => (
            <Row key={`${String(fault.at)}-${fault.message}`} label={fault.message} plain value={formatClock(fault.at)} detail={fault.fatal ? "fatal" : "caught by the global handler"} />
          ))
        )}
      </Section>

      <Section title="Build">
        <Row label="App" plain value={`${appVersion} · dev`} />
        <Row label="Channel" plain value={INFO.channel} />
        <Row label="Running" plain value={INFO.createdAt === null ? INFO.running : `${INFO.running} · ${formatDateTime(INFO.createdAt)}`} />
        <Row label="Runtime" plain value={INFO.runtime.slice(0, 12)} />
        <Row label="Launch" plain value={INFO.launchMs === null ? "--" : `${ms(INFO.launchMs)} ms`} />
        <Row label="Started" plain value={formatDateTime(diagnostics.startedAt)} />
      </Section>

      <View className="px-[22px] py-6">
        <Button label="Share report" onPress={share} />
      </View>
    </Screen>
  );
}
