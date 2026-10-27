import * as Schema from "effect/Schema";

import { Scope } from "./auth.ts";
import { Command, CommandReceipt } from "./commands.ts";
import { GuardSettings, GuardState } from "./guard.ts";
import { CommandId, DeviceId, LanKey, NonNegativeInt, PositiveInt } from "./ids.ts";
import { PairPrompt } from "./lan.ts";
import { AppsSnapshot, ProcessesSnapshot, ProcessesWatchInput } from "./processes.ts";
import { HistoryRangeInput, HistoryRangeResult, LiveSample, Topic } from "./stats.ts";
import { AudioState, BRIDGE_VERSION, KeepAwakeState, MacInfo, SystemEvent } from "./system.ts";
import { ActivityLevel } from "./activity.ts";
import { ClipDestination, ClipFileName, ClipId, ClipPlacement, ClipPolicy, ClipStats, MacClip } from "./clips.ts";
import { Drop, DropId, DropPeer, DropPolicy, MacDropFile, ReceivedDropFile } from "./drop.ts";
import { FsAccess, FsDevice, FsListResult, FsPath, FsRoot, FsThumb } from "./fs.ts";
import { MacTerminal, TerminalId } from "./terminal.ts";
import { Device } from "./auth.ts";

const RequestId = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(64));

export const Query = Schema.Union([
  Schema.TaggedStruct("History", { input: HistoryRangeInput }),
  Schema.TaggedStruct("Apps", {}),
  Schema.TaggedStruct("Clipboard", {}),
  Schema.TaggedStruct("SetGuard", { settings: GuardSettings }),
  /** Clone a copied file, or zip a copied folder, into `clips/` so phones can download it. */
  Schema.TaggedStruct("ClipMaterialize", { id: ClipId, kind: Schema.Literals(["file", "folder"]), origin: Schema.String }),
  /** Put clips on the Mac clipboard or into Downloads. */
  Schema.TaggedStruct("ClipPut", {
    items: Schema.Array(ClipPlacement),
    to: ClipDestination,
    folder: Schema.NullOr(Schema.String),
    deviceName: Schema.String,
  }),
  Schema.TaggedStruct("FsThumbs", { paths: Schema.Array(FsPath), pixels: PositiveInt }),
  Schema.TaggedStruct("FsTrash", { paths: Schema.Array(FsPath), deviceName: Schema.String }),
  Schema.TaggedStruct("FsOpen", { path: FsPath }),
]);
export type Query = typeof Query.Type;

export const QueryResult = Schema.Union([
  Schema.TaggedStruct("History", { result: HistoryRangeResult }),
  Schema.TaggedStruct("Apps", { result: AppsSnapshot }),
  Schema.TaggedStruct("Clipboard", { text: Schema.NullOr(Schema.String) }),
  Schema.TaggedStruct("SetGuard", { settings: GuardSettings }),
  Schema.TaggedStruct("ClipMaterialize", { stored: ClipFileName, bytes: NonNegativeInt, files: Schema.NullOr(NonNegativeInt) }),
  Schema.TaggedStruct("ClipPut", { placed: NonNegativeInt }),
  Schema.TaggedStruct("FsThumbs", { thumbs: Schema.Array(FsThumb) }),
  Schema.TaggedStruct("FsTrash", { trashed: NonNegativeInt }),
  Schema.TaggedStruct("FsOpen", {}),
]);
export type QueryResult = typeof QueryResult.Type;

export const AdminOp = Schema.Union([
  Schema.TaggedStruct("CreatePairing", {}),
  Schema.TaggedStruct("ListDevices", {}),
  Schema.TaggedStruct("RevokeDevice", { deviceId: DeviceId }),
  Schema.TaggedStruct("SetScopes", { deviceId: DeviceId, scopes: Schema.Array(Scope) }),
  Schema.TaggedStruct("ResolvePairPrompt", { id: Schema.String, allow: Schema.Boolean }),
  Schema.TaggedStruct("FsDevices", {}),
  Schema.TaggedStruct("FsRoots", { device: DeviceId }),
  Schema.TaggedStruct("FsList", { device: DeviceId, path: FsPath, offset: NonNegativeInt }),
  Schema.TaggedStruct("FsThumbs", { device: DeviceId, paths: Schema.Array(FsPath) }),
  Schema.TaggedStruct("FsPull", { device: DeviceId, paths: Schema.Array(FsPath) }),
]);
export type AdminOp = typeof AdminOp.Type;

export const AdminResult = Schema.Union([
  Schema.TaggedStruct("CreatePairing", { code: Schema.String, url: Schema.NullOr(Schema.String), expiresAt: NonNegativeInt }),
  Schema.TaggedStruct("ListDevices", { devices: Schema.Array(Device) }),
  Schema.TaggedStruct("RevokeDevice", {}),
  Schema.TaggedStruct("SetScopes", {}),
  Schema.TaggedStruct("ResolvePairPrompt", {}),
  Schema.TaggedStruct("FsDevices", { devices: Schema.Array(FsDevice) }),
  Schema.TaggedStruct("FsRoots", { roots: Schema.Array(FsRoot) }),
  Schema.TaggedStruct("FsList", { result: FsListResult }),
  Schema.TaggedStruct("FsThumbs", { thumbs: Schema.Array(FsThumb) }),
  Schema.TaggedStruct("FsPull", { files: NonNegativeInt }),
]);
export type AdminResult = typeof AdminResult.Type;

export const ServeState = Schema.Literals(["off", "starting", "serving", "degraded"]);
export type ServeState = typeof ServeState.Type;

export const TailscaleStep = Schema.Literals(["install", "start", "signin", "magicdns", "https", "ready", "external"]);
export type TailscaleStep = typeof TailscaleStep.Type;

export const GatewayStatus = Schema.Struct({
  serve: ServeState,
  url: Schema.NullOr(Schema.String),
  detail: Schema.NullOr(Schema.String),
  ownerLogin: Schema.NullOr(Schema.String),
  clients: NonNegativeInt,
  lan: Schema.NullOr(Schema.Struct({ port: PositiveInt, key: LanKey, reachable: Schema.Boolean })),
  setup: Schema.Struct({ step: TailscaleStep, url: Schema.NullOr(Schema.String) }),
});
export type GatewayStatus = typeof GatewayStatus.Type;

export const ToApp = Schema.Union([
  Schema.Struct({ t: Schema.Literal("hello"), v: Schema.Literal(BRIDGE_VERSION) }),
  Schema.Struct({
    t: Schema.Literal("need"),
    topics: Schema.Array(Topic),
    intervalMs: PositiveInt,
    processes: Schema.NullOr(ProcessesWatchInput),
    guard: Schema.Boolean,
  }),
  Schema.Struct({
    t: Schema.Literal("cmd"),
    id: CommandId,
    deviceId: DeviceId,
    deviceName: Schema.String,
    command: Command,
  }),
  Schema.Struct({ t: Schema.Literal("cancel"), id: CommandId }),
  Schema.Struct({ t: Schema.Literal("query"), id: RequestId, q: Query }),
  Schema.Struct({
    t: Schema.Literal("adminResult"),
    id: RequestId,
    ok: Schema.NullOr(AdminResult),
    error: Schema.NullOr(Schema.String),
  }),
  Schema.Struct({ t: Schema.Literal("status"), status: GatewayStatus }),
  Schema.Struct({ t: Schema.Literal("pairPrompt"), prompt: PairPrompt }),
  Schema.Struct({ t: Schema.Literal("pairPromptEnded"), id: Schema.String }),
  Schema.Struct({ t: Schema.Literal("clipStats"), stats: ClipStats }),
  Schema.Struct({ t: Schema.Literal("drop"), drop: Drop }),
  Schema.Struct({ t: Schema.Literal("dropRemoved"), id: DropId }),
  Schema.Struct({ t: Schema.Literal("dropReceived"), id: DropId, from: DropPeer, files: Schema.Array(ReceivedDropFile), dest: Schema.optionalKey(FsPath) }),
  Schema.Struct({ t: Schema.Literal("terminals"), sessions: Schema.Array(MacTerminal) }),
]);
export type ToApp = typeof ToApp.Type;

export const FromApp = Schema.Union([
  Schema.Struct({
    t: Schema.Literal("hello"),
    v: Schema.Literal(BRIDGE_VERSION),
    mac: MacInfo,
    keepAwake: KeepAwakeState,
  }),
  Schema.Struct({ t: Schema.Literal("sample"), data: LiveSample }),
  Schema.Struct({ t: Schema.Literal("processes"), data: ProcessesSnapshot }),
  Schema.Struct({ t: Schema.Literal("guard"), data: GuardState }),
  Schema.Struct({ t: Schema.Literal("audio"), data: AudioState }),
  Schema.Struct({ t: Schema.Literal("receipt"), receipt: CommandReceipt }),
  Schema.Struct({ t: Schema.Literal("event"), event: SystemEvent }),
  Schema.Struct({
    t: Schema.Literal("result"),
    id: RequestId,
    ok: Schema.NullOr(QueryResult),
    error: Schema.NullOr(Schema.String),
  }),
  Schema.Struct({ t: Schema.Literal("admin"), id: RequestId, op: AdminOp }),
  Schema.Struct({
    t: Schema.Literal("log"),
    level: ActivityLevel,
    kind: Schema.String,
    data: Schema.Record(Schema.String, Schema.Unknown),
  }),
  Schema.Struct({ t: Schema.Literal("clip"), clip: MacClip }),
  Schema.Struct({ t: Schema.Literal("clipPolicy"), policy: ClipPolicy }),
  Schema.Struct({ t: Schema.Literal("clipClear") }),
  Schema.Struct({
    t: Schema.Literal("dropSend"),
    to: Schema.Array(DeviceId).check(Schema.isMinLength(1), Schema.isMaxLength(8)),
    files: Schema.Array(MacDropFile).check(Schema.isMinLength(1), Schema.isMaxLength(10_000)),
  }),
  Schema.Struct({ t: Schema.Literal("dropDecision"), id: DropId, accept: Schema.Boolean }),
  Schema.Struct({ t: Schema.Literal("dropCancel"), id: DropId }),
  Schema.Struct({ t: Schema.Literal("dropPause"), id: DropId, paused: Schema.Boolean }),
  Schema.Struct({ t: Schema.Literal("dropPolicy"), policy: DropPolicy }),
  Schema.Struct({ t: Schema.Literal("fsPolicy"), access: FsAccess }),
  Schema.Struct({ t: Schema.Literal("terminalEnd"), id: Schema.NullOr(TerminalId), deviceId: Schema.NullOr(DeviceId) }),
]);
export type FromApp = typeof FromApp.Type;

export const MAX_BRIDGE_LINE_BYTES = 1_048_576;
