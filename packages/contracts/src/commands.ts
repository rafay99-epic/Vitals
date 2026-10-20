import * as Schema from "effect/Schema";

import { AlertId, CommandId, DeviceId, EpochMs, Fraction, NonNegativeInt, PositiveInt, ProcessRef } from "./ids.ts";

const Grace = NonNegativeInt.check(Schema.isLessThanOrEqualTo(60));

export const ProcessActionKind = Schema.Literals([
  "throttle",
  "unthrottle",
  "pause",
  "resume",
  "terminate",
  "kill",
]);
export type ProcessActionKind = typeof ProcessActionKind.Type;

export const ProcessAction = Schema.Struct({
  target: ProcessRef,
  action: ProcessActionKind,
});
export type ProcessAction = typeof ProcessAction.Type;

export const AppRef = Schema.Struct({
  pid: PositiveInt,
  bundleId: Schema.NullOr(Schema.String),
});
export type AppRef = typeof AppRef.Type;

export const EmulatorKind = Schema.Literals(["android", "ios"]);
export type EmulatorKind = typeof EmulatorKind.Type;

export const Command = Schema.Union([
  Schema.TaggedStruct("KeepAwake", {
    until: Schema.NullOr(EpochMs),
    display: Schema.Boolean,
    whileProcess: Schema.NullOr(ProcessRef),
  }),
  Schema.TaggedStruct("AllowSleep", {}),
  Schema.TaggedStruct("DisplayOff", {}),
  Schema.TaggedStruct("Lock", {}),
  Schema.TaggedStruct("Sleep", { graceSeconds: Grace }),
  Schema.TaggedStruct("Restart", { graceSeconds: Grace }),
  Schema.TaggedStruct("ShutDown", { graceSeconds: Grace }),
  Schema.TaggedStruct("LogOut", { graceSeconds: Grace }),
  Schema.TaggedStruct("Processes", {
    actions: Schema.Array(ProcessAction).check(Schema.isMinLength(1), Schema.isMaxLength(64)),
  }),
  Schema.TaggedStruct("QuitApp", { app: AppRef }),
  Schema.TaggedStruct("HideApp", { app: AppRef }),
  Schema.TaggedStruct("ForceQuitApp", { app: AppRef }),
  Schema.TaggedStruct("LaunchApp", { bundleId: Schema.String.check(Schema.isMinLength(1)) }),
  Schema.TaggedStruct("StopEmulator", { kind: EmulatorKind, id: Schema.String.check(Schema.isMinLength(1)) }),
  Schema.TaggedStruct("SetVolume", { level: Fraction }),
  Schema.TaggedStruct("SetMuted", { muted: Schema.Boolean }),
  Schema.TaggedStruct("ClipboardSet", { text: Schema.String.check(Schema.isMaxLength(100_000)) }),
  Schema.TaggedStruct("OpenUrl", { url: Schema.String.check(Schema.isPattern(/^https?:\/\/\S+$/)) }),
  Schema.TaggedStruct("Locate", {}),
  Schema.TaggedStruct("CalmDown", { alertId: Schema.NullOr(AlertId) }),
  Schema.TaggedStruct("UndoCalm", {}),
]);
export type Command = typeof Command.Type;
export type CommandTag = Command["_tag"];

const DESTRUCTIVE_TAGS: ReadonlySet<CommandTag> = new Set([
  "Restart",
  "ShutDown",
  "LogOut",
  "ForceQuitApp",
  "StopEmulator",
]);

export const isDestructive = (command: Command): boolean =>
  DESTRUCTIVE_TAGS.has(command._tag) ||
  (command._tag === "Processes" &&
    command.actions.some((item) => item.action === "terminate" || item.action === "kill"));

export const CommandStatus = Schema.Literals(["pending", "running", "done", "failed", "cancelled", "rejected"]);
export type CommandStatus = typeof CommandStatus.Type;

export const TERMINAL_STATUSES: ReadonlySet<CommandStatus> = new Set(["done", "failed", "cancelled", "rejected"]);

export const CommandReceipt = Schema.Struct({
  id: CommandId,
  kind: Schema.String,
  deviceId: DeviceId,
  status: CommandStatus,
  createdAt: EpochMs,
  deadlineAt: Schema.NullOr(EpochMs),
  finishedAt: Schema.NullOr(EpochMs),
  error: Schema.NullOr(Schema.String),
});
export type CommandReceipt = typeof CommandReceipt.Type;

export const CommandRunInput = Schema.Struct({
  commandId: CommandId,
  command: Command,
});
export type CommandRunInput = typeof CommandRunInput.Type;

export const CommandCancelInput = Schema.Struct({ commandId: CommandId });
export type CommandCancelInput = typeof CommandCancelInput.Type;
