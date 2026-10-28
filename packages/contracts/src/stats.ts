import * as Schema from "effect/Schema";

import { EpochMs, NonNegativeInt, Percent } from "./ids.ts";

export const Topic = Schema.Literals([
  "cpu",
  "gpu",
  "thermal",
  "fans",
  "memory",
  "battery",
  "power",
  "network",
  "disk",
]);
export type Topic = typeof Topic.Type;

const Reading = Schema.NullOr(Schema.Number);

export const CoreSample = Schema.Struct({
  id: NonNegativeInt,
  percent: Percent,
  isPerformance: Schema.Boolean,
});
export type CoreSample = typeof CoreSample.Type;

export const CpuSample = Schema.Struct({
  overall: Schema.NullOr(Percent),
  performance: Schema.NullOr(Percent),
  efficiency: Schema.NullOr(Percent),
  perCore: Schema.Array(CoreSample),
});
export type CpuSample = typeof CpuSample.Type;

export const GpuSample = Schema.Struct({
  utilization: Schema.NullOr(Percent),
  memoryUsedBytes: Reading,
  coreCount: Schema.NullOr(NonNegativeInt),
  rendererUtilization: Schema.optionalKey(Percent),
  tilerUtilization: Schema.optionalKey(Percent),
  memoryTotalBytes: Schema.optionalKey(Schema.Number),
});
export type GpuSample = typeof GpuSample.Type;

export const ThermalState = Schema.Literals(["nominal", "fair", "serious", "critical"]);
export type ThermalState = typeof ThermalState.Type;

export const SensorKind = Schema.Literals(["cpu", "gpu", "storage", "battery", "other"]);
export type SensorKind = typeof SensorKind.Type;

export const SensorSample = Schema.Struct({
  id: Schema.String,
  label: Schema.String,
  kind: SensorKind,
  celsius: Schema.Number,
});
export type SensorSample = typeof SensorSample.Type;

export const ThermalSample = Schema.Struct({
  state: ThermalState,
  cpuC: Reading,
  gpuC: Reading,
  storageC: Reading,
  batteryC: Reading,
  sensors: Schema.Array(SensorSample),
});
export type ThermalSample = typeof ThermalSample.Type;

export const FanSample = Schema.Struct({
  id: NonNegativeInt,
  rpm: Schema.Number,
  minRpm: Schema.Number,
  maxRpm: Schema.Number,
});
export type FanSample = typeof FanSample.Type;

export const MemoryPressure = Schema.Literals(["normal", "warning", "critical"]);
export type MemoryPressure = typeof MemoryPressure.Type;

export const MemorySample = Schema.Struct({
  totalBytes: Schema.Number,
  usedBytes: Schema.Number,
  appBytes: Schema.Number,
  wiredBytes: Schema.Number,
  compressedBytes: Schema.Number,
  cachedBytes: Schema.Number,
  freeBytes: Schema.Number,
  swapUsedBytes: Schema.Number,
  swapTotalBytes: Schema.Number,
  pressure: MemoryPressure,
});
export type MemorySample = typeof MemorySample.Type;

export const AdapterSample = Schema.Struct({
  watts: Schema.optionalKey(Schema.Number),
  name: Schema.optionalKey(Schema.String),
  wireless: Schema.Boolean,
  deliveredWatts: Schema.optionalKey(Schema.Number),
  voltage: Schema.optionalKey(Schema.Number),
  amperage: Schema.optionalKey(Schema.Number),
});
export type AdapterSample = typeof AdapterSample.Type;

export const BatterySample = Schema.Struct({
  percent: Percent,
  charging: Schema.Boolean,
  externalPower: Schema.Boolean,
  watts: Reading,
  timeRemainingMinutes: Schema.NullOr(NonNegativeInt),
  cycleCount: Schema.NullOr(NonNegativeInt),
  healthPercent: Reading,
  temperatureC: Reading,
  condition: Schema.String,
  fullyCharged: Schema.optionalKey(Schema.Boolean),
  designCapacityMah: Schema.optionalKey(NonNegativeInt),
  maxCapacityMah: Schema.optionalKey(NonNegativeInt),
  remainingCapacityMah: Schema.optionalKey(NonNegativeInt),
  designCycleCount: Schema.optionalKey(NonNegativeInt),
  voltage: Schema.optionalKey(Schema.Number),
  amperage: Schema.optionalKey(Schema.Number),
  adapter: Schema.optionalKey(AdapterSample),
});
export type BatterySample = typeof BatterySample.Type;

export const PowerSample = Schema.Struct({
  cpuWatts: Schema.Number,
  gpuWatts: Schema.Number,
  aneWatts: Schema.Number,
});
export type PowerSample = typeof PowerSample.Type;

export const LinkKind = Schema.Literals(["wifi", "ethernet", "other"]);
export type LinkKind = typeof LinkKind.Type;

export const NetworkLinkSample = Schema.Struct({
  name: Schema.String,
  label: Schema.String,
  kind: LinkKind,
  inBytesPerSec: Schema.Number,
  outBytesPerSec: Schema.Number,
  active: Schema.Boolean,
});
export type NetworkLinkSample = typeof NetworkLinkSample.Type;

export const WifiSample = Schema.Struct({
  ssid: Schema.optionalKey(Schema.String),
  rssi: Schema.optionalKey(Schema.Int),
  noise: Schema.optionalKey(Schema.Int),
  txRateMbps: Schema.optionalKey(Schema.Number),
  channel: Schema.optionalKey(NonNegativeInt),
  band: Schema.optionalKey(Schema.String),
});
export type WifiSample = typeof WifiSample.Type;

export const NetworkSample = Schema.Struct({
  inBytesPerSec: Schema.Number,
  outBytesPerSec: Schema.Number,
  wifiRssi: Schema.NullOr(Schema.Int),
  primaryInterface: Schema.NullOr(Schema.String),
  totalInBytes: Schema.optionalKey(Schema.Number),
  totalOutBytes: Schema.optionalKey(Schema.Number),
  links: Schema.optionalKey(Schema.Array(NetworkLinkSample)),
  wifi: Schema.optionalKey(WifiSample),
});
export type NetworkSample = typeof NetworkSample.Type;

export const DriveHealthSample = Schema.Struct({
  model: Schema.optionalKey(Schema.String),
  wearPercent: NonNegativeInt,
  readBytes: Schema.Number,
  writtenBytes: Schema.Number,
  powerOnHours: NonNegativeInt,
  unsafeShutdowns: NonNegativeInt,
  sparePercent: NonNegativeInt,
  celsius: Schema.optionalKey(Schema.Number),
  warning: Schema.Boolean,
});
export type DriveHealthSample = typeof DriveHealthSample.Type;

export const DiskSample = Schema.Struct({
  readBytesPerSec: Schema.Number,
  writeBytesPerSec: Schema.Number,
  freeBytes: Schema.optionalKey(Schema.Number),
  totalBytes: Schema.optionalKey(Schema.Number),
  volume: Schema.optionalKey(Schema.String),
  health: Schema.optionalKey(DriveHealthSample),
});
export type DiskSample = typeof DiskSample.Type;

export const LiveSample = Schema.Struct({
  seq: NonNegativeInt,
  at: EpochMs,
  cpu: Schema.optionalKey(CpuSample),
  gpu: Schema.optionalKey(GpuSample),
  thermal: Schema.optionalKey(ThermalSample),
  fans: Schema.optionalKey(Schema.Array(FanSample)),
  memory: Schema.optionalKey(MemorySample),
  battery: Schema.optionalKey(Schema.NullOr(BatterySample)),
  power: Schema.optionalKey(Schema.NullOr(PowerSample)),
  systemWatts: Schema.optionalKey(Schema.Number),
  network: Schema.optionalKey(NetworkSample),
  disk: Schema.optionalKey(DiskSample),
});
export type LiveSample = typeof LiveSample.Type;

export const StatsLiveInput = Schema.Struct({
  topics: Schema.Array(Topic).check(Schema.isMinLength(1)),
});
export type StatsLiveInput = typeof StatsLiveInput.Type;

export const HistorySeries = Schema.Literals([
  "cpu",
  "gpu",
  "cpuTemp",
  "gpuTemp",
  "fanRpm",
  "memoryUsedGb",
  "battery",
  "socWatts",
  "batteryWatts",
  "networkIn",
  "networkOut",
  "diskRead",
  "diskWrite",
]);
export type HistorySeries = typeof HistorySeries.Type;

export const HistoryRangeInput = Schema.Struct({
  series: Schema.Array(HistorySeries).check(Schema.isMinLength(1), Schema.isMaxLength(6)),
  from: EpochMs,
  to: EpochMs,
  points: NonNegativeInt.check(Schema.isBetween({ minimum: 10, maximum: 300 })),
}).check(Schema.makeFilter((input) => input.from < input.to || "from must be before to"));
export type HistoryRangeInput = typeof HistoryRangeInput.Type;

export const HistoryBucket = Schema.Struct({
  t: EpochMs,
  min: Schema.Number,
  avg: Schema.Number,
  max: Schema.Number,
});
export type HistoryBucket = typeof HistoryBucket.Type;

export const HistoryRangeResult = Schema.Struct({
  series: Schema.Array(
    Schema.Struct({ name: HistorySeries, buckets: Schema.Array(HistoryBucket) }),
  ),
});
export type HistoryRangeResult = typeof HistoryRangeResult.Type;
