import * as Schema from "effect/Schema";
import * as Rpc from "effect/rpc/Rpc";
import * as RpcGroup from "effect/rpc/RpcGroup";
import * as RpcMiddleware from "effect/rpc/RpcMiddleware";

import { ActivityIngestInput, ActivityIngestResult } from "./activity.ts";
import { AuthError, CommandRejected, Unavailable } from "./auth.ts";
import { CommandCancelInput, CommandReceipt, CommandRunInput } from "./commands.ts";
import { GuardSettings, GuardState } from "./guard.ts";
import { LanKey } from "./ids.ts";
import { AppsSnapshot, ProcessesSnapshot, ProcessesWatchInput } from "./processes.ts";
import { HistoryRangeInput, HistoryRangeResult, LiveSample, StatsLiveInput } from "./stats.ts";
import { Hello, SequencedEvent, SystemEventsInput } from "./system.ts";

const Empty = Schema.Struct({});

export const ServerHello = Rpc.make("server.hello", { payload: Empty, success: Hello, error: AuthError });

export const StatsLive = Rpc.make("stats.live", {
  payload: StatsLiveInput,
  success: LiveSample,
  error: Schema.Union([AuthError, Unavailable]),
  stream: true,
});

export const HistoryRange = Rpc.make("history.range", {
  payload: HistoryRangeInput,
  success: HistoryRangeResult,
  error: Schema.Union([AuthError, Unavailable]),
});

export const SystemEvents = Rpc.make("system.events", {
  payload: SystemEventsInput,
  success: SequencedEvent,
  error: AuthError,
  stream: true,
});

export const ProcessesWatch = Rpc.make("processes.watch", {
  payload: ProcessesWatchInput,
  success: ProcessesSnapshot,
  error: Schema.Union([AuthError, Unavailable]),
  stream: true,
});

export const AppsList = Rpc.make("apps.list", {
  payload: Empty,
  success: AppsSnapshot,
  error: Schema.Union([AuthError, Unavailable]),
});

export const CommandRun = Rpc.make("command.run", {
  payload: CommandRunInput,
  success: CommandReceipt,
  error: Schema.Union([AuthError, CommandRejected, Unavailable]),
});

export const CommandCancel = Rpc.make("command.cancel", {
  payload: CommandCancelInput,
  success: CommandReceipt,
  error: Schema.Union([AuthError, CommandRejected]),
});

export const CommandLog = Rpc.make("command.log", {
  payload: Empty,
  success: CommandReceipt,
  error: AuthError,
  stream: true,
});

export const GuardWatch = Rpc.make("guard.watch", {
  payload: Empty,
  success: GuardState,
  error: Schema.Union([AuthError, Unavailable]),
  stream: true,
});

export const GuardUpdate = Rpc.make("guard.update", {
  payload: GuardSettings,
  success: GuardSettings,
  error: Schema.Union([AuthError, Unavailable]),
});

export const ClipboardGet = Rpc.make("clipboard.get", {
  payload: Empty,
  success: Schema.Struct({ text: Schema.NullOr(Schema.String) }),
  error: Schema.Union([AuthError, Unavailable]),
});

export const ActivityIngest = Rpc.make("activity.ingest", {
  payload: ActivityIngestInput,
  success: ActivityIngestResult,
  error: AuthError,
});

export const DeviceLanKey = Rpc.make("device.lanKey", {
  payload: Schema.Struct({ key: LanKey }),
  success: Empty,
  error: AuthError,
});

export const DeviceForget = Rpc.make("device.forget", { payload: Empty, success: Empty, error: AuthError });

export class ScopeAuthorization extends RpcMiddleware.Service<ScopeAuthorization>()(
  "@vitals/contracts/ScopeAuthorization",
  { error: AuthError },
) {}

export const VitalsRpc = RpcGroup.make(
  ServerHello,
  StatsLive,
  HistoryRange,
  SystemEvents,
  ProcessesWatch,
  AppsList,
  CommandRun,
  CommandCancel,
  CommandLog,
  GuardWatch,
  GuardUpdate,
  ClipboardGet,
  ActivityIngest,
  DeviceLanKey,
  DeviceForget,
).middleware(ScopeAuthorization);

export type VitalsRpcs = RpcGroup.Rpcs<typeof VitalsRpc>;
export type VitalsMethod = VitalsRpcs["_tag"];
