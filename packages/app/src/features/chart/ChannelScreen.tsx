import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import type { FanSample } from "@vitals/contracts";
import { formatBytes, formatCelsius, formatPercent, formatRate, formatRpm, formatWatts } from "@vitals/shared";
import { ArcGauge, Heatstrip, Row, Screen, Section, Sparkline, StackedArea, Stat, colors } from "@vitals/ui";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import type { LiveStackParams } from "../../navigation/types.ts";
import { HistoryPanel } from "./HistoryPanel.tsx";
import { useLatest, useLiveTopics } from "./hooks.ts";

type Props = NativeStackScreenProps<LiveStackParams, "Metric">;

const NO_FANS: ReadonlyArray<FanSample> = [];

export function MetricScreen({ route }: Props) {
  switch (route.params.kind) {
    case "cpu":
      return <CpuDetail />;
    case "gpu":
      return <GpuDetail />;
    case "thermal":
      return <ThermalDetail />;
    case "fans":
      return <FansDetail />;
    case "memory":
      return <MemoryDetail />;
    case "battery":
      return <BatteryDetail />;
    case "power":
      return <PowerDetail />;
    case "network":
      return <NetworkDetail />;
  }
}

function CpuDetail() {
  useLiveTopics(["cpu"]);
  const remote = useRemote();
  const cpu = useLatest((sample) => sample?.cpu ?? null);
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row gap-6">
        <Stat label="Total" value={formatPercent(cpu?.overall ?? null)} />
        <Stat label="Performance" value={formatPercent(cpu?.performance ?? null)} />
        <Stat label="Efficiency" value={formatPercent(cpu?.efficiency ?? null)} />
      </View>
      <Section title="Live">
        <Sparkline source={remote.live.series("cpu")} height={120} max={100} />
      </Section>
      {(cpu?.perCore.length ?? 0) > 0 ? (
        <Section title={`Cores · ${cpu?.perCore.length ?? 0}`}>
          <Heatstrip source={remote.live.cores} />
        </Section>
      ) : null}
      <HistoryPanel series="cpu" format={(value) => formatPercent(value)} ceiling={100} />
    </Screen>
  );
}

function GpuDetail() {
  useLiveTopics(["gpu", "thermal", "power"]);
  const remote = useRemote();
  const gpu = useLatest((sample) => sample?.gpu ?? null);
  const temp = useLatest((sample) => sample?.thermal?.gpuC ?? null);
  const watts = useLatest((sample) => sample?.power?.gpuWatts ?? null);
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row gap-6">
        <Stat label="Busy" value={formatPercent(gpu?.utilization ?? null)} />
        <Stat label="Temp" value={formatCelsius(temp)} />
        <Stat label="Power" value={formatWatts(watts)} />
      </View>
      <Section title="Live">
        <Sparkline source={remote.live.series("gpu")} height={120} max={100} color={colors.violet} />
      </Section>
      <Row label="Memory in use" value={gpu?.memoryUsedBytes === null || gpu?.memoryUsedBytes === undefined ? "--" : formatBytes(gpu.memoryUsedBytes)} />
      <Row label="GPU cores" value={gpu?.coreCount === null || gpu?.coreCount === undefined ? "--" : String(gpu.coreCount)} />
      <HistoryPanel series="gpu" format={(value) => formatPercent(value)} ceiling={100} color={colors.violet} />
    </Screen>
  );
}

function ThermalDetail() {
  useLiveTopics(["thermal"]);
  const remote = useRemote();
  const thermal = useLatest((sample) => sample?.thermal ?? null);
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row gap-6">
        <Stat label="CPU" value={formatCelsius(thermal?.cpuC ?? null)} />
        <Stat label="GPU" value={formatCelsius(thermal?.gpuC ?? null)} />
        <Stat label="State" value={thermal?.state ?? "--"} tone={thermal?.state === "serious" || thermal?.state === "critical" ? "bad" : "ink"} />
      </View>
      <Section title="CPU average">
        <Sparkline source={remote.live.series("cpuTemp")} height={120} min={20} max={110} color={colors.warn} />
      </Section>
      <Section title="Sensors">
        {thermal?.storageC === null || thermal?.storageC === undefined ? null : <Row label="SSD" value={formatCelsius(thermal.storageC)} />}
        {thermal?.batteryC === null || thermal?.batteryC === undefined ? null : <Row label="Battery" value={formatCelsius(thermal.batteryC)} />}
        {(thermal?.sensors ?? []).map((sensor) => (
          <Row key={sensor.id} label={sensor.label} value={formatCelsius(sensor.celsius)} />
        ))}
      </Section>
      <HistoryPanel series="cpuTemp" format={(value) => formatCelsius(value)} floor={20} color={colors.warn} />
    </Screen>
  );
}

function FansDetail() {
  useLiveTopics(["fans"]);
  const remote = useRemote();
  const fans = useLatest((sample) => sample?.fans ?? NO_FANS);
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row flex-wrap gap-4">
        {fans.map((fan) => (
          <ArcGauge
            key={fan.id}
            fraction={fan.maxRpm > fan.minRpm ? (fan.rpm - fan.minRpm) / (fan.maxRpm - fan.minRpm) : null}
            label={`Fan ${fan.id + 1}`}
            value={formatRpm(fan.rpm)}
          />
        ))}
      </View>
      {fans.length === 0 ? <Row label="No fans" detail="This Mac is fanless." /> : null}
      <Section title="Live">
        <Sparkline source={remote.live.series("fan")} height={100} />
      </Section>
      {fans.map((fan) => (
        <Row key={fan.id} label={`Fan ${fan.id + 1} range`} value={`${Math.round(fan.minRpm)} to ${Math.round(fan.maxRpm)} rpm`} />
      ))}
      <HistoryPanel series="fanRpm" format={(value) => formatRpm(value)} />
    </Screen>
  );
}

function MemoryDetail() {
  useLiveTopics(["memory"]);
  const remote = useRemote();
  const memory = useLatest((sample) => sample?.memory ?? null);
  const layers = [
    { source: remote.live.series("memApp"), color: colors.accent },
    { source: remote.live.series("memWired"), color: colors.violet },
    { source: remote.live.series("memCompressed"), color: colors.warn },
  ];
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row gap-6">
        <Stat label="Used" value={memory === null ? "--" : formatBytes(memory.usedBytes)} />
        <Stat label="Pressure" value={memory?.pressure ?? "--"} tone={memory?.pressure === "critical" ? "bad" : memory?.pressure === "warning" ? "warn" : "ok"} />
        <Stat label="Swap" value={memory === null ? "--" : formatBytes(memory.swapUsedBytes)} />
      </View>
      <Section title="App · Wired · Compressed">
        <StackedArea layers={layers} max={memory?.totalBytes ?? 1} />
      </Section>
      <Section title="Breakdown">
        <Row label="App memory" value={memory === null ? "--" : formatBytes(memory.appBytes)} />
        <Row label="Wired" value={memory === null ? "--" : formatBytes(memory.wiredBytes)} />
        <Row label="Compressed" value={memory === null ? "--" : formatBytes(memory.compressedBytes)} />
        <Row label="Cached files" value={memory === null ? "--" : formatBytes(memory.cachedBytes)} />
        <Row label="Free" value={memory === null ? "--" : formatBytes(memory.freeBytes)} />
        <Row label="Total" value={memory === null ? "--" : formatBytes(memory.totalBytes, 0)} />
      </Section>
      <HistoryPanel series="memoryUsedGb" format={(value) => `${value.toFixed(1)} GB`} color={colors.ok} />
    </Screen>
  );
}

function BatteryDetail() {
  useLiveTopics(["battery"]);
  const remote = useRemote();
  const battery = useLatest((sample) => sample?.battery ?? null);
  if (battery === null) {
    return (
      <Screen insetTop={false}>
        <Row label="No battery" detail="This Mac runs on wall power only." />
      </Screen>
    );
  }
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row gap-6">
        <Stat label="Charge" value={formatPercent(battery.percent)} />
        <Stat label="Health" value={formatPercent(battery.healthPercent)} />
        <Stat label="Power" value={formatWatts(battery.watts)} />
      </View>
      <Section title="Live">
        <Sparkline source={remote.live.series("battery")} height={100} max={100} color={colors.ok} />
      </Section>
      <Section title="Details">
        <Row label="State" value={battery.charging ? "Charging" : battery.externalPower ? "On power" : "On battery"} />
        <Row label="Time left" value={battery.timeRemainingMinutes === null ? "--" : `${Math.floor(battery.timeRemainingMinutes / 60)}h ${battery.timeRemainingMinutes % 60}m`} />
        <Row label="Cycles" value={battery.cycleCount === null ? "--" : String(battery.cycleCount)} />
        <Row label="Temperature" value={formatCelsius(battery.temperatureC)} />
        <Row label="Condition" value={battery.condition} />
      </Section>
      <HistoryPanel series="battery" format={(value) => formatPercent(value)} ceiling={100} color={colors.ok} />
    </Screen>
  );
}

function PowerDetail() {
  useLiveTopics(["power"]);
  const remote = useRemote();
  const power = useLatest((sample) => sample?.power ?? null);
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row gap-6">
        <Stat label="CPU" value={formatWatts(power?.cpuWatts ?? null)} />
        <Stat label="GPU" value={formatWatts(power?.gpuWatts ?? null)} />
        <Stat label="ANE" value={formatWatts(power?.aneWatts ?? null)} />
      </View>
      <Section title="CPU · GPU watts">
        <StackedArea
          layers={[
            { source: remote.live.series("cpuWatts"), color: colors.warn },
            { source: remote.live.series("gpuWatts"), color: colors.violet },
          ]}
          max={40}
        />
      </Section>
      <HistoryPanel series="socWatts" format={(value) => formatWatts(value)} color={colors.warn} />
    </Screen>
  );
}

function NetworkDetail() {
  useLiveTopics(["network", "disk"]);
  const remote = useRemote();
  const network = useLatest((sample) => sample?.network ?? null);
  const disk = useLatest((sample) => sample?.disk ?? null);
  return (
    <Screen insetTop={false}>
      <View className="mt-4 flex-row gap-6">
        <Stat label="Down" value={network === null ? "--" : formatRate(network.inBytesPerSec)} />
        <Stat label="Up" value={network === null ? "--" : formatRate(network.outBytesPerSec)} />
      </View>
      <Section title="Download">
        <Sparkline source={remote.live.series("netIn")} height={80} />
      </Section>
      <Section title="Upload">
        <Sparkline source={remote.live.series("netOut")} height={80} color={colors.violet} />
      </Section>
      <Section title="Disk">
        <Row label="Read" value={disk === null ? "--" : formatRate(disk.readBytesPerSec)} />
        <Row label="Write" value={disk === null ? "--" : formatRate(disk.writeBytesPerSec)} />
        <Row label="Interface" value={network?.primaryInterface ?? "--"} />
        <Row label="Wi-Fi signal" value={network?.wifiRssi === null || network?.wifiRssi === undefined ? "--" : `${network.wifiRssi} dBm`} />
      </Section>
      <HistoryPanel series="networkIn" format={(value) => formatRate(value)} />
    </Screen>
  );
}
