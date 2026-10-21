import * as Schema from "effect/Schema";

import { Scope } from "./auth.ts";
import { CommandReceipt } from "./commands.ts";
import { EpochMs, NonNegativeInt, ProcessRef } from "./ids.ts";
import { Alert } from "./guard.ts";
import { MacRoutes } from "./lan.ts";
import { ThermalState } from "./stats.ts";

export const PROTOCOL_VERSION = 1 as const;
export const BRIDGE_VERSION = 1 as const;

export const MacInfo = Schema.Struct({
  name: Schema.String,
  model: Schema.String,
  chip: Schema.String,
  os: Schema.String,
  coreCount: NonNegativeInt,
  memoryBytes: Schema.Number,
  hasBattery: Schema.Boolean,
  hasFans: Schema.Boolean,
  vitalsVersion: Schema.String,
  channel: Schema.Literals(["stable", "nightly", "dev"]),
});
export type MacInfo = typeof MacInfo.Type;

export const KeepAwakeState = Schema.Struct({
  active: Schema.Boolean,
  display: Schema.Boolean,
  until: Schema.NullOr(EpochMs),
  whileProcess: Schema.NullOr(ProcessRef),
});
export type KeepAwakeState = typeof KeepAwakeState.Type;

export const SystemEvent = Schema.Union([
  Schema.TaggedStruct("WillSleep", { at: EpochMs }),
  Schema.TaggedStruct("DidWake", { at: EpochMs }),
  Schema.TaggedStruct("WillPowerOff", { at: EpochMs }),
  Schema.TaggedStruct("ThermalChanged", { at: EpochMs, state: ThermalState }),
  Schema.TaggedStruct("KeepAwakeChanged", { at: EpochMs, state: KeepAwakeState }),
  Schema.TaggedStruct("AlertRaised", { at: EpochMs, alert: Alert }),
  Schema.TaggedStruct("AlertCleared", { at: EpochMs, alert: Alert }),
  Schema.TaggedStruct("CommandUpdated", { at: EpochMs, receipt: CommandReceipt }),
]);
export type SystemEvent = typeof SystemEvent.Type;

export const SequencedEvent = Schema.Struct({
  seq: NonNegativeInt,
  event: SystemEvent,
});
export type SequencedEvent = typeof SequencedEvent.Type;

export const SystemEventsInput = Schema.Struct({
  afterSeq: Schema.NullOr(NonNegativeInt),
});
export type SystemEventsInput = typeof SystemEventsInput.Type;

export const Hello = Schema.Struct({
  protocol: Schema.Literal(PROTOCOL_VERSION),
  mac: Schema.NullOr(MacInfo),
  keepAwake: Schema.NullOr(KeepAwakeState),
  lastEventSeq: NonNegativeInt,
  alerts: Schema.Array(Alert),
  serverTime: EpochMs,
  scopes: Schema.Array(Scope),
  routes: Schema.optional(MacRoutes),
});
export type Hello = typeof Hello.Type;
