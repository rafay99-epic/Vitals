import type { LiveSample } from "@vitals/contracts";
import { formatCelsius, formatPercent, formatRpm } from "@vitals/shared";
import { type Channel, channels, colors, EmptyState, type KeyValue, KeyValueGrid, Mono, Row, Section, Serif, Spark, StackBar, type StackPart } from "@vitals/ui";
import type { ReactNode } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { useLatest } from "../../state/useVitals.ts";
import { bytes, fixed } from "../../state/vitals.ts";

const reading = (key: string, value: number | null | undefined, digits = 0, unit = ""): KeyValue => ({ key, value: fixed(value, digits), unit: value === null || value === undefined ? undefined : unit });

const byteItem = (key: string, value: number | null | undefined): KeyValue => {
  const parts = bytes(value);
  return { key, value: parts.value, unit: parts.unit === "" ? undefined : parts.unit };
};

const rateItem = (key: string, value: number | null | undefined): KeyValue => {
  const parts = bytes(value);
  return { key, value: parts.value, unit: parts.unit === "" ? undefined : `${parts.unit}/s` };
};

const cpuOf = (sample: LiveSample | null) => sample?.cpu ?? null;
const gpuOf = (sample: LiveSample | null) => sample?.gpu ?? null;
const memoryOf = (sample: LiveSample | null) => sample?.memory ?? null;
const thermalOf = (sample: LiveSample | null) => sample?.thermal ?? null;
const fansOf = (sample: LiveSample | null) => sample?.fans ?? null;
const batteryOf = (sample: LiveSample | null) => sample?.battery;
const powerOf = (sample: LiveSample | null) => sample?.power ?? null;
const systemWattsOf = (sample: LiveSample | null) => sample?.systemWatts ?? null;
const networkOf = (sample: LiveSample | null) => sample?.network ?? null;
const diskOf = (sample: LiveSample | null) => sample?.disk ?? null;

function CoreCell({ label, values, value }: { readonly label: string; readonly values: ReadonlyArray<number>; readonly value: number }) {
  return (
    <View className="w-1/2 flex-row items-center gap-2 border-b border-line px-[22px] py-2" accessible accessibilityLabel={`Core ${label}, ${formatPercent(value)}`}>
      <Mono className="w-7 text-[10px]">{label}</Mono>
      <Spark channel="pulse" values={values} width={64} height={20} max={100} />
      <Serif size="s" className="ml-auto">
        {fixed(value)}
      </Serif>
    </View>
  );
}

function PulseDetail() {
  const remote = useRemote();
  const cpu = useLatest(cpuOf);
  const rows = remote.live.cores.rows();
  const performance = cpu?.perCore.filter((core) => core.isPerformance).length ?? 0;
  return (
    <>
      <KeyValueGrid
        items={[
          reading("Total", cpu?.overall, 0, "%"),
          reading("Performance", cpu?.performance, 0, "%"),
          reading("Efficiency", cpu?.efficiency, 0, "%"),
          { key: "Cores", value: cpu === null ? "--" : String(cpu.perCore.length), unit: cpu === null ? undefined : `${String(performance)} P` },
        ]}
      />
      {cpu === null || cpu.perCore.length === 0 ? null : (
        <Section title="Cores" trailing="% busy">
          <View className="flex-row flex-wrap">
            {cpu.perCore.map((core, index) => (
              <CoreCell key={core.id} label={`${core.isPerformance ? "P" : "E"}${String(index + 1)}`} values={rows[index] ?? []} value={core.percent} />
            ))}
          </View>
        </Section>
      )}
    </>
  );
}

function PressDetail() {
  const memory = useLatest(memoryOf);
  if (memory === null) return <KeyValueGrid items={[{ key: "Used", value: "--" }]} />;
  const parts: ReadonlyArray<StackPart> = [
    { key: "app", label: "App memory", value: memory.appBytes, color: channels.press.color, display: bytesText(memory.appBytes) },
    { key: "wired", label: "Wired", value: memory.wiredBytes, color: colors.ink2, display: bytesText(memory.wiredBytes) },
    { key: "compressed", label: "Compressed", value: memory.compressedBytes, color: channels.temp.color, display: bytesText(memory.compressedBytes) },
    { key: "cached", label: "Cached files", value: memory.cachedBytes, color: colors.dim, display: bytesText(memory.cachedBytes) },
    { key: "free", label: "Free", value: memory.freeBytes, color: colors.line3, display: bytesText(memory.freeBytes) },
  ];
  return (
    <>
      <KeyValueGrid
        items={[
          byteItem("Used", memory.usedBytes),
          { key: "Pressure", value: memory.pressure, tone: memory.pressure === "normal" ? "ink" : "press" },
          byteItem("Swap", memory.swapUsedBytes),
          byteItem("Total", memory.totalBytes),
        ]}
      />
      <Section title="Composition" trailing={bytesText(memory.totalBytes)}>
        <StackBar parts={parts} total={memory.totalBytes} />
      </Section>
    </>
  );
}

const bytesText = (value: number): string => {
  const parts = bytes(value);
  return `${parts.value} ${parts.unit}`;
};

const rateText = (value: number): string => `${bytesText(value)}/s`;

function TempDetail() {
  const thermal = useLatest(thermalOf);
  return (
    <>
      <KeyValueGrid
        items={[
          reading("CPU die", thermal?.cpuC, 0, "°C"),
          reading("GPU", thermal?.gpuC, 0, "°C"),
          reading("SSD", thermal?.storageC, 0, "°C"),
          reading("Battery", thermal?.batteryC, 0, "°C"),
          { key: "Thermal pressure", value: thermal?.state ?? "--", tone: thermal?.state === "serious" || thermal?.state === "critical" ? "temp" : "ink" },
        ]}
      />
      {(thermal?.sensors.length ?? 0) === 0 ? null : (
        <Section title="Sensors" trailing={`${String(thermal?.sensors.length ?? 0)} readings`}>
          {(thermal?.sensors ?? []).map((sensor) => (
            <Row key={sensor.id} label={sensor.label} value={formatCelsius(sensor.celsius)} plain />
          ))}
        </Section>
      )}
    </>
  );
}

function RespDetail() {
  const fans = useLatest(fansOf);
  if (fans !== null && fans.length === 0) return <EmptyState title="This Mac is fanless." detail="TEMP still reports thermal pressure." />;
  return (
    <Section title="Fans" trailing={fans === null ? undefined : `${String(fans.length)} fans`}>
      {(fans ?? []).map((fan) => (
        <Row key={fan.id} label={`Fan ${String(fan.id + 1)}`} value={formatRpm(fan.rpm)} detail={`range ${String(Math.round(fan.minRpm))} to ${String(Math.round(fan.maxRpm))} rpm`} plain />
      ))}
    </Section>
  );
}

const batteryState = (charging: boolean, externalPower: boolean, full: boolean): string => {
  if (charging) return "Charging";
  if (full && externalPower) return "Charged";
  return externalPower ? "On power" : "On battery";
};

const batteryFlow = (watts: number | null | undefined): KeyValue => {
  if (watts === null || watts === undefined) return reading("Draw", watts);
  return reading(watts > 0 ? "Charging" : "Draw", Math.abs(watts), 1, "W");
};

const timeLeft = (minutes: number | null): string => (minutes === null ? "--" : `${String(Math.floor(minutes / 60))} h ${String(minutes % 60)} m`);

function OxyDetail() {
  const battery = useLatest(batteryOf);
  if (battery === null) return <EmptyState title="This Mac runs on wall power only." detail="OXY is hidden on its Chart." />;
  const adapter = battery?.adapter;
  return (
    <>
      <KeyValueGrid
        items={[
          reading("Charge", battery?.percent, 0, "%"),
          { key: "State", value: battery === undefined ? "--" : batteryState(battery.charging, battery.externalPower, battery.fullyCharged === true) },
          batteryFlow(battery?.watts),
          { key: battery?.charging === true ? "Full in" : "Time left", value: battery === undefined ? "--" : timeLeft(battery.timeRemainingMinutes) },
          reading("Voltage", battery?.voltage, 2, "V"),
          reading("Current", battery?.amperage, 2, "A"),
          reading("Temperature", battery?.temperatureC, 0, "°C"),
        ]}
      />
      <Section title="Health" trailing={battery?.healthPercent === null || battery?.healthPercent === undefined ? undefined : `${fixed(battery.healthPercent)}% of new`}>
        <KeyValueGrid
          items={[
            reading("Max capacity", battery?.maxCapacityMah, 0, "mAh"),
            reading("Design capacity", battery?.designCapacityMah, 0, "mAh"),
            { key: "Cycles", value: fixed(battery?.cycleCount), unit: battery === undefined || battery.cycleCount === null || battery.designCycleCount === undefined ? undefined : `of ${String(battery.designCycleCount)}` },
            reading("Charge left", battery?.remainingCapacityMah, 0, "mAh"),
            { key: "Condition", value: battery?.condition ?? "--", tone: battery === undefined || battery.condition === "Normal" ? "ink" : "temp" },
          ]}
        />
      </Section>
      {adapter === undefined ? null : (
        <Section title="Adapter" trailing={adapter.wireless ? "wireless" : undefined}>
          <KeyValueGrid
            items={[
              { key: "Adapter", value: adapter.name ?? "--" },
              reading("Rated", adapter.watts, 0, "W"),
              reading("Delivering", adapter.deliveredWatts, 1, "W"),
              { key: "Negotiated", value: adapter.voltage === undefined || adapter.amperage === undefined ? "--" : `${fixed(adapter.voltage, 1)} V · ${fixed(adapter.amperage, 2)} A` },
            ]}
          />
        </Section>
      )}
    </>
  );
}

function EegDetail() {
  const gpu = useLatest(gpuOf);
  const power = useLatest(powerOf);
  const thermal = useLatest(thermalOf);
  const total = gpu?.memoryTotalBytes;
  return (
    <>
      <KeyValueGrid
        items={[
          reading("Busy", gpu?.utilization, 0, "%"),
          reading("Renderer", gpu?.rendererUtilization, 0, "%"),
          reading("Tiler", gpu?.tilerUtilization, 0, "%"),
          reading("GPU cores", gpu?.coreCount),
          reading("GPU power", power?.gpuWatts, 1, "W"),
          reading("Neural Engine", power?.aneWatts, 1, "W"),
          reading("GPU temperature", thermal?.gpuC, 0, "°C"),
        ]}
      />
      {gpu === null || gpu.memoryUsedBytes === null ? null : (
        <Section title="GPU memory" trailing={total === undefined ? bytesText(gpu.memoryUsedBytes) : `${bytesText(gpu.memoryUsedBytes)} of ${bytesText(total)}`}>
          {total === undefined ? null : (
            <StackBar
              parts={[
                { key: "used", label: "In use", value: gpu.memoryUsedBytes, color: channels.eeg.color, display: bytesText(gpu.memoryUsedBytes) },
                { key: "free", label: "Available", value: Math.max(0, total - gpu.memoryUsedBytes), color: colors.line3, display: bytesText(Math.max(0, total - gpu.memoryUsedBytes)) },
              ]}
              total={total}
            />
          )}
        </Section>
      )}
    </>
  );
}

function DripDetail() {
  const power = useLatest(powerOf);
  const system = useLatest(systemWattsOf);
  const battery = useLatest(batteryOf);
  return (
    <KeyValueGrid
      items={[
        reading("Whole Mac", system, 1, "W"),
        reading("CPU", power?.cpuWatts, 1, "W"),
        reading("GPU", power?.gpuWatts, 1, "W"),
        reading("Neural Engine", power?.aneWatts, 1, "W"),
        reading("Battery", battery?.watts, 1, "W"),
      ]}
    />
  );
}

function TeleDetail() {
  const network = useLatest(networkOf);
  const wifi = network?.wifi;
  const links = network?.links ?? [];
  return (
    <>
      <KeyValueGrid
        items={[
          rateItem("Down", network?.inBytesPerSec),
          rateItem("Up", network?.outBytesPerSec),
          { key: "Interface", value: network?.primaryInterface ?? "--" },
          byteItem("Down since start", network?.totalInBytes),
          byteItem("Up since start", network?.totalOutBytes),
        ]}
      />
      {wifi === undefined ? null : (
        <Section title="Wi-Fi" trailing={wifi.ssid}>
          <KeyValueGrid
            items={[
              reading("Signal", wifi.rssi, 0, "dBm"),
              reading("Noise", wifi.noise, 0, "dBm"),
              reading("Link speed", wifi.txRateMbps, 0, "Mbps"),
              { key: "Band", value: wifi.band === undefined ? "--" : wifi.channel === undefined ? wifi.band : `${wifi.band} · ch ${String(wifi.channel)}` },
            ]}
          />
        </Section>
      )}
      {links.length === 0 ? null : (
        <Section title="Links" trailing={`${String(links.filter((link) => link.active).length)} active`}>
          {links.map((link) => (
            <Row key={link.name} label={link.label} value={link.active ? `↓ ${rateText(link.inBytesPerSec)}` : "idle"} detail={link.active ? `${link.name} · ↑ ${rateText(link.outBytesPerSec)}` : link.name} plain />
          ))}
        </Section>
      )}
    </>
  );
}

function DiskDetail() {
  const disk = useLatest(diskOf);
  const health = disk?.health;
  const free = disk?.freeBytes;
  const total = disk?.totalBytes;
  return (
    <>
      <KeyValueGrid items={[rateItem("Read", disk?.readBytesPerSec), rateItem("Write", disk?.writeBytesPerSec), byteItem("Free", free), byteItem("Size", total)]} />
      {free === undefined || total === undefined ? null : (
        <Section title={disk?.volume ?? "Startup disk"} trailing={`${bytesText(free)} free`}>
          <StackBar
            parts={[
              { key: "used", label: "Used", value: total - free, color: channels.disk.color, display: bytesText(total - free) },
              { key: "free", label: "Free", value: free, color: colors.line3, display: bytesText(free) },
            ]}
            total={total}
          />
        </Section>
      )}
      {health === undefined ? null : (
        <Section title="Drive health" trailing={health.model}>
          <KeyValueGrid
            items={[
              { key: "Worn", value: `${String(health.wearPercent)}`, unit: "%", tone: health.warning || health.wearPercent >= 80 ? "temp" : "ink" },
              { key: "Spare", value: `${String(health.sparePercent)}`, unit: "%" },
              byteItem("Written", health.writtenBytes),
              byteItem("Read", health.readBytes),
              reading("Powered on", health.powerOnHours, 0, "h"),
              reading("Unsafe shutdowns", health.unsafeShutdowns),
              reading("Temperature", health.celsius, 0, "°C"),
            ]}
          />
        </Section>
      )}
    </>
  );
}

export const CHANNEL_DETAILS: Record<Channel, () => ReactNode> = {
  pulse: PulseDetail,
  press: PressDetail,
  temp: TempDetail,
  resp: RespDetail,
  oxy: OxyDetail,
  eeg: EegDetail,
  drip: DripDetail,
  tele: TeleDetail,
  disk: DiskDetail,
};
