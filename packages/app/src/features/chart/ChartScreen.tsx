import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { formatBytes, formatCelsius, formatPercent, formatRate, formatRpm, formatWatts } from "@vitals/shared";
import { colors, Screen, Section, type SeriesSource, Sparkline } from "@vitals/ui";
import { Pressable, Text, View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import type { LiveStackParams, MetricKind } from "../../navigation/types.ts";
import { useLatest, useLiveTopics } from "./hooks.ts";
import { StatusHeader } from "./StatusHeader.tsx";

type Props = NativeStackScreenProps<LiveStackParams, "Live">;

export function LiveScreen({ navigation }: Props) {
  useLiveTopics(["cpu", "gpu", "thermal", "fans", "memory", "battery", "power", "network"]);
  const remote = useRemote();
  const open = (kind: MetricKind) => navigation.navigate("Metric", { kind });
  const cpu = useLatest((sample) => sample?.cpu?.overall ?? null);
  const gpu = useLatest((sample) => sample?.gpu?.utilization ?? null);
  const temp = useLatest((sample) => sample?.thermal?.cpuC ?? null);
  const thermalState = useLatest((sample) => sample?.thermal?.state ?? null);
  const fan = useLatest((sample) => sample?.fans?.[0]?.rpm ?? null);
  const hasFans = useLatest((sample) => (sample?.fans?.length ?? 0) > 0);
  const memoryUsed = useLatest((sample) => sample?.memory?.usedBytes ?? null);
  const memoryTotal = useLatest((sample) => sample?.memory?.totalBytes ?? null);
  const pressure = useLatest((sample) => sample?.memory?.pressure ?? null);
  const battery = useLatest((sample) => sample?.battery ?? null);
  const watts = useLatest((sample) => (sample?.power === undefined || sample.power === null ? null : sample.power.cpuWatts + sample.power.gpuWatts + sample.power.aneWatts));
  const netIn = useLatest((sample) => sample?.network?.inBytesPerSec ?? null);
  const netOut = useLatest((sample) => sample?.network?.outBytesPerSec ?? null);

  return (
    <Screen>
      <StatusHeader />
      <Section title="Now">
        <MetricRow label="CPU" value={formatPercent(cpu)} source={remote.live.series("cpu")} max={100} onPress={() => open("cpu")} />
        <MetricRow label="GPU" value={formatPercent(gpu)} source={remote.live.series("gpu")} max={100} color={colors.violet} onPress={() => open("gpu")} />
        <MetricRow
          label="Temperature"
          value={formatCelsius(temp)}
          detail={thermalState === null || thermalState === "nominal" ? undefined : `thermal ${thermalState}`}
          source={remote.live.series("cpuTemp")}
          min={20}
          max={110}
          color={colors.warn}
          onPress={() => open("thermal")}
        />
        {hasFans ? <MetricRow label="Fans" value={formatRpm(fan)} source={remote.live.series("fan")} onPress={() => open("fans")} /> : null}
        <MetricRow
          label="Memory"
          value={memoryUsed === null || memoryTotal === null ? "--" : `${formatBytes(memoryUsed)} / ${formatBytes(memoryTotal, 0)}`}
          detail={pressure === null || pressure === "normal" ? undefined : `pressure ${pressure}`}
          source={remote.live.series("memoryUsed")}
          max={memoryTotal ?? undefined}
          color={pressure === "critical" ? colors.bad : pressure === "warning" ? colors.warn : colors.ok}
          onPress={() => open("memory")}
        />
        {battery === null ? null : (
          <MetricRow
            label="Battery"
            value={formatPercent(battery.percent)}
            detail={battery.charging ? "charging" : battery.externalPower ? "on power" : battery.timeRemainingMinutes === null ? undefined : `${Math.round(battery.timeRemainingMinutes / 60)}h left`}
            source={remote.live.series("battery")}
            max={100}
            color={colors.ok}
            onPress={() => open("battery")}
          />
        )}
        <MetricRow label="Power" value={formatWatts(watts)} source={remote.live.series("socWatts")} color={colors.warn} onPress={() => open("power")} />
        <MetricRow
          label="Network"
          value={netIn === null || netOut === null ? "--" : `↓ ${formatRate(netIn)}  ↑ ${formatRate(netOut)}`}
          source={remote.live.series("netIn")}
          onPress={() => open("network")}
        />
      </Section>
    </Screen>
  );
}

function MetricRow({
  label,
  value,
  detail,
  source,
  onPress,
  min = 0,
  max,
  color = colors.accent,
}: {
  readonly label: string;
  readonly value: string;
  readonly detail?: string | undefined;
  readonly source: SeriesSource;
  readonly onPress: () => void;
  readonly min?: number;
  readonly max?: number | undefined;
  readonly color?: string;
}) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={`${label} ${value}`} className="border-b border-line py-3 active:bg-line">
      <View className="flex-row items-baseline justify-between">
        <Text className="text-[15px] text-ink">{label}</Text>
        <Text className="font-mono text-[15px] text-ink">{value}</Text>
      </View>
      {detail === undefined ? null : <Text className="font-mono text-[11px] text-warn">{detail}</Text>}
      <View className="mt-2">
        <Sparkline source={source} height={28} color={color} min={min} {...(max === undefined ? {} : { max })} />
      </View>
    </Pressable>
  );
}
