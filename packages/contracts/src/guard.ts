import * as Schema from "effect/Schema";

import { AlertId, EpochMs, NonNegativeInt, PositiveInt } from "./ids.ts";
import { ProcessAction } from "./commands.ts";
import { GroupTotals } from "./processes.ts";
import { MemoryPressure, ThermalState } from "./stats.ts";

export const GuardRuleKind = Schema.Literals([
  "memoryPressure",
  "swapGrowth",
  "cpuSaturated",
  "agentOverload",
  "emulatorStack",
  "thermal",
]);
export type GuardRuleKind = typeof GuardRuleKind.Type;

export const Severity = Schema.Literals(["warning", "critical"]);
export type Severity = typeof Severity.Type;

export const GuardRule = Schema.Struct({
  kind: GuardRuleKind,
  enabled: Schema.Boolean,
  threshold: Schema.Number.check(Schema.isGreaterThanOrEqualTo(0)),
  holdSeconds: NonNegativeInt,
});
export type GuardRule = typeof GuardRule.Type;

export const GuardSettings = Schema.Struct({
  enabled: Schema.Boolean,
  cooldownSeconds: PositiveInt,
  rules: Schema.Array(GuardRule),
});
export type GuardSettings = typeof GuardSettings.Type;

export const CalmPlan = Schema.Struct({
  actions: Schema.Array(ProcessAction),
  summary: Schema.String,
});
export type CalmPlan = typeof CalmPlan.Type;

export const Alert = Schema.Struct({
  id: AlertId,
  rule: GuardRuleKind,
  severity: Severity,
  summary: Schema.String,
  raisedAt: EpochMs,
  clearedAt: Schema.NullOr(EpochMs),
  groups: Schema.Array(GroupTotals),
  plan: CalmPlan,
});
export type Alert = typeof Alert.Type;

export const OpenAlerts = Schema.Struct({
  lastSeq: NonNegativeInt,
  alerts: Schema.Array(Alert),
});
export type OpenAlerts = typeof OpenAlerts.Type;

export const GuardState = Schema.Struct({
  settings: GuardSettings,
  pressure: MemoryPressure,
  thermal: ThermalState,
  swapUsedBytes: Schema.Number,
  groups: Schema.Array(GroupTotals),
  active: Schema.Array(Alert),
  calmApplied: Schema.Boolean,
});
export type GuardState = typeof GuardState.Type;
