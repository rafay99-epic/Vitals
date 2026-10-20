import * as Schema from "effect/Schema";

import { EpochMs, NonNegativeInt, PositiveInt } from "./ids.ts";

export const ProcessGroupId = Schema.Literals(["agents", "emulators", "devServers", "browsers", "other", "protected"]);
export type ProcessGroupId = typeof ProcessGroupId.Type;

export const ProcessRow = Schema.Struct({
  pid: PositiveInt,
  startTimeMs: NonNegativeInt,
  name: Schema.String,
  group: ProcessGroupId,
  cpuPercent: Schema.Number,
  memoryBytes: Schema.Number,
  throttled: Schema.Boolean,
  paused: Schema.Boolean,
});
export type ProcessRow = typeof ProcessRow.Type;

export const GroupTotals = Schema.Struct({
  group: ProcessGroupId,
  count: NonNegativeInt,
  cpuPercent: Schema.Number,
  memoryBytes: Schema.Number,
});
export type GroupTotals = typeof GroupTotals.Type;

export const ProcessesSnapshot = Schema.Struct({
  at: EpochMs,
  rows: Schema.Array(ProcessRow),
  groups: Schema.Array(GroupTotals),
});
export type ProcessesSnapshot = typeof ProcessesSnapshot.Type;

export const ProcessesWatchInput = Schema.Struct({
  sortBy: Schema.Literals(["cpu", "memory"]),
  limit: PositiveInt.check(Schema.isLessThanOrEqualTo(200)),
});
export type ProcessesWatchInput = typeof ProcessesWatchInput.Type;

export const RunningApp = Schema.Struct({
  pid: PositiveInt,
  bundleId: Schema.NullOr(Schema.String),
  name: Schema.String,
  active: Schema.Boolean,
  hidden: Schema.Boolean,
});
export type RunningApp = typeof RunningApp.Type;

export const Emulator = Schema.Struct({
  kind: Schema.Literals(["android", "ios"]),
  id: Schema.String,
  name: Schema.String,
  pid: Schema.NullOr(PositiveInt),
});
export type Emulator = typeof Emulator.Type;

export const AppsSnapshot = Schema.Struct({
  running: Schema.Array(RunningApp),
  emulators: Schema.Array(Emulator),
});
export type AppsSnapshot = typeof AppsSnapshot.Type;
