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
});
export type BatterySample = typeof BatterySample.Type;

export const PowerSample = Schema.Struct({
  cpuWatts: Schema.Number,
  gpuWatts: Schema.Number,
  aneWatts: Schema.Number,
});
export type PowerSample = typeof PowerSample.Type;

export const NetworkSample = Schema.Struct({
  inBytesPerSec: Schema.Number,
  outBytesPerSec: Schema.Number,
  wifiRssi: Schema.NullOr(Schema.Int),
  primaryInterface: Schema.NullOr(Schema.String),
});
export type NetworkSample = typeof NetworkSample.Type;

export const DiskSample = Schema.Struct({
  readBytesPerSec: Schema.Number,
  writeBytesPerSec: Schema.Number,
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
