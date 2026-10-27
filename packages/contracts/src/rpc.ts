import * as Schema from "effect/Schema";
import * as Rpc from "effect/rpc/Rpc";
import * as RpcGroup from "effect/rpc/RpcGroup";
import * as RpcMiddleware from "effect/rpc/RpcMiddleware";

import { ActivityIngestInput, ActivityIngestResult } from "./activity.ts";
import { AuthError, CommandRejected, Unavailable } from "./auth.ts";
import {
  Clip,
  ClipChunk,
  ClipEvent,
  ClipSendBegin,
  ClipSendBegun,
  ClipSendChunk,
  ClipSendFinish,
  ClipsPinInput,
  ClipsPutInput,
  ClipsPutResult,
  ClipsReadInput,
  ClipsRemoveInput,
} from "./clips.ts";
import { DropEvent, DropIdInput, DropOffered, DropOfferInput, DropReceivedInput, DropTicket, Drop } from "./drop.ts";
import { CommandCancelInput, CommandReceipt, CommandRunInput } from "./commands.ts";
import {
  FsEntry,
  FsFolderInput,
  FsListInput,
  FsListResult,
  FsPathInput,
  FsPathsInput,
  FsRenameInput,
  FsRootsResult,
  FsSearchInput,
  FsSearchResult,
  FsThumbsInput,
  FsThumbsResult,
  FsTrashResult,
} from "./fs.ts";
import { GuardSettings, GuardState } from "./guard.ts";
import { TerminalAttachInput, TerminalEvent, TerminalIdInput, TerminalInfo, TerminalList, TerminalSize, TerminalWriteInput } from "./terminal.ts";
import { LanKey, NonNegativeInt } from "./ids.ts";
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

const ClipError = Schema.Union([AuthError, Unavailable, CommandRejected]);

export const ClipsWatch = Rpc.make("clips.watch", { payload: Empty, success: ClipEvent, error: ClipError, stream: true });
export const ClipsRead = Rpc.make("clips.read", { payload: ClipsReadInput, success: ClipChunk, error: ClipError });
export const ClipsPin = Rpc.make("clips.pin", { payload: ClipsPinInput, success: Clip, error: ClipError });
export const ClipsRemove = Rpc.make("clips.remove", { payload: ClipsRemoveInput, success: Empty, error: ClipError });
export const ClipsSendBegin = Rpc.make("clips.send.begin", { payload: ClipSendBegin, success: ClipSendBegun, error: ClipError });
export const ClipsSendChunk = Rpc.make("clips.send.chunk", {
  payload: ClipSendChunk,
  success: Schema.Struct({ received: NonNegativeInt }),
  error: ClipError,
});
export const ClipsSendFinish = Rpc.make("clips.send.finish", { payload: ClipSendFinish, success: Clip, error: ClipError });
export const ClipsPut = Rpc.make("clips.put", { payload: ClipsPutInput, success: ClipsPutResult, error: ClipError });

const DropError = Schema.Union([AuthError, Unavailable, CommandRejected]);

export const DropWatch = Rpc.make("drop.watch", { payload: Empty, success: DropEvent, error: DropError, stream: true });
export const DropOffer = Rpc.make("drop.offer", { payload: DropOfferInput, success: DropOffered, error: DropError });
export const DropAccept = Rpc.make("drop.accept", { payload: DropIdInput, success: DropOffered, error: DropError });
export const DropDecline = Rpc.make("drop.decline", { payload: DropIdInput, success: Drop, error: DropError });
export const DropCancel = Rpc.make("drop.cancel", { payload: DropIdInput, success: Drop, error: DropError });
export const DropTicketRefresh = Rpc.make("drop.ticket", { payload: DropIdInput, success: DropTicket, error: DropError });
export const DropReceived = Rpc.make("drop.received", { payload: DropReceivedInput, success: Drop, error: DropError });

const FsError = Schema.Union([AuthError, Unavailable, CommandRejected]);

export const FsRoots = Rpc.make("fs.roots", { payload: Empty, success: FsRootsResult, error: FsError });
export const FsList = Rpc.make("fs.list", { payload: FsListInput, success: FsListResult, error: FsError });
export const FsSearch = Rpc.make("fs.search", { payload: FsSearchInput, success: FsSearchResult, error: FsError });
export const FsThumbs = Rpc.make("fs.thumbs", { payload: FsThumbsInput, success: FsThumbsResult, error: FsError });
export const FsGet = Rpc.make("fs.get", { payload: FsPathsInput, success: DropOffered, error: FsError });
export const FsOpen = Rpc.make("fs.open", { payload: FsPathInput, success: Empty, error: FsError });
export const FsRename = Rpc.make("fs.rename", { payload: FsRenameInput, success: FsEntry, error: FsError });
export const FsFolder = Rpc.make("fs.folder", { payload: FsFolderInput, success: FsEntry, error: FsError });
export const FsTrash = Rpc.make("fs.trash", { payload: FsPathsInput, success: FsTrashResult, error: FsError });

const TerminalError = Schema.Union([AuthError, Unavailable, CommandRejected]);

export const TerminalListRpc = Rpc.make("terminal.list", { payload: Empty, success: TerminalList, error: TerminalError });
export const TerminalOpen = Rpc.make("terminal.open", { payload: TerminalSize, success: TerminalInfo, error: TerminalError });
export const TerminalAttach = Rpc.make("terminal.attach", { payload: TerminalAttachInput, success: TerminalEvent, error: TerminalError, stream: true });
export const TerminalWrite = Rpc.make("terminal.write", { payload: TerminalWriteInput, success: Empty, error: TerminalError });
export const TerminalResize = Rpc.make("terminal.resize", { payload: TerminalAttachInput, success: Empty, error: TerminalError });
export const TerminalClose = Rpc.make("terminal.close", { payload: TerminalIdInput, success: Empty, error: TerminalError });

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
  ClipsWatch,
  ClipsRead,
  ClipsPin,
  ClipsRemove,
  ClipsSendBegin,
  ClipsSendChunk,
  ClipsSendFinish,
  ClipsPut,
  DropWatch,
  DropOffer,
  DropAccept,
  DropDecline,
  DropCancel,
  DropTicketRefresh,
  DropReceived,
  FsRoots,
  FsList,
  FsSearch,
  FsThumbs,
  FsGet,
  FsOpen,
  FsRename,
  FsFolder,
  FsTrash,
  TerminalListRpc,
  TerminalOpen,
  TerminalAttach,
  TerminalWrite,
  TerminalResize,
  TerminalClose,
  ActivityIngest,
  DeviceLanKey,
  DeviceForget,
).middleware(ScopeAuthorization);

export type VitalsRpcs = RpcGroup.Rpcs<typeof VitalsRpc>;
export type VitalsMethod = VitalsRpcs["_tag"];
