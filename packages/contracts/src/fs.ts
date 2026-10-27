import * as Schema from "effect/Schema";

import { Platform } from "./auth.ts";
import { DeviceId, EpochMs, NonNegativeInt, PositiveInt } from "./ids.ts";

export const FS_LIMITS = {
  page: 500,
  search: 200,
  thumbs: 24,
  pull: 10_000,
  thumbPixels: 192,
  recent: 120,
} as const;

export const FsPath = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(4096), Schema.isPattern(/^\/[^\0]*$/));
export type FsPath = typeof FsPath.Type;

export const FsKind = Schema.Literals(["folder", "file", "package", "link"]);
export type FsKind = typeof FsKind.Type;

export const FsEntry = Schema.Struct({
  name: Schema.String,
  path: FsPath,
  kind: FsKind,
  size: NonNegativeInt,
  modifiedAt: EpochMs,
});
export type FsEntry = typeof FsEntry.Type;

export const FsPlace = Schema.Literals(["home", "desktop", "documents", "downloads", "movies", "music", "pictures", "disk", "volume", "photos", "storage", "folder"]);
export type FsPlace = typeof FsPlace.Type;

export const FsRoot = Schema.Struct({
  label: Schema.String,
  path: FsPath,
  place: FsPlace,
});
export type FsRoot = typeof FsRoot.Type;

export const FsAccess = Schema.Literals(["folders", "everything"]);
export type FsAccess = typeof FsAccess.Type;

export const FsRootsResult = Schema.Struct({ roots: Schema.Array(FsRoot) });
export type FsRootsResult = typeof FsRootsResult.Type;

export const FsSort = Schema.Literals(["name", "date", "size"]);
export type FsSort = typeof FsSort.Type;

const Target = Schema.optionalKey(DeviceId);

export const FsRootsInput = Schema.Struct({ device: Target });
export type FsRootsInput = typeof FsRootsInput.Type;

export const FsListInput = Schema.Struct({
  device: Target,
  path: FsPath,
  sort: FsSort,
  hidden: Schema.Boolean,
  offset: NonNegativeInt,
  limit: PositiveInt.check(Schema.isLessThanOrEqualTo(FS_LIMITS.page)),
});
export type FsListInput = typeof FsListInput.Type;

export const FsListResult = Schema.Struct({
  path: FsPath,
  parent: Schema.NullOr(FsPath),
  entries: Schema.Array(FsEntry),
  total: NonNegativeInt,
});
export type FsListResult = typeof FsListResult.Type;

export const FsSearchInput = Schema.Struct({
  query: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(128)),
  limit: PositiveInt.check(Schema.isLessThanOrEqualTo(FS_LIMITS.search)),
});
export type FsSearchInput = typeof FsSearchInput.Type;

export const FsSearchResult = Schema.Struct({
  entries: Schema.Array(FsEntry),
  truncated: Schema.Boolean,
});
export type FsSearchResult = typeof FsSearchResult.Type;

export const FsPathsInput = Schema.Struct({
  device: Target,
  paths: Schema.Array(FsPath).check(Schema.isMinLength(1), Schema.isMaxLength(FS_LIMITS.pull)),
});
export type FsPathsInput = typeof FsPathsInput.Type;

export const FsThumbsInput = Schema.Struct({
  device: Target,
  paths: Schema.Array(FsPath).check(Schema.isMinLength(1), Schema.isMaxLength(FS_LIMITS.thumbs)),
});
export type FsThumbsInput = typeof FsThumbsInput.Type;

export const FsThumb = Schema.Struct({
  path: FsPath,
  jpeg: Schema.NullOr(Schema.String),
});
export type FsThumb = typeof FsThumb.Type;

export const FsThumbsResult = Schema.Struct({ thumbs: Schema.Array(FsThumb) });
export type FsThumbsResult = typeof FsThumbsResult.Type;

export const FsPathInput = Schema.Struct({ path: FsPath });
export type FsPathInput = typeof FsPathInput.Type;

/** What a device page shows in rows: newest first, files only. */
export const FsRecentKind = Schema.Literals(["photos", "screenshots", "downloads", "documents"]);
export type FsRecentKind = typeof FsRecentKind.Type;

export const FsRecentInput = Schema.Struct({
  device: Target,
  kind: FsRecentKind,
  offset: NonNegativeInt,
  limit: PositiveInt.check(Schema.isLessThanOrEqualTo(FS_LIMITS.recent)),
});
export type FsRecentInput = typeof FsRecentInput.Type;

export const FsRecentResult = Schema.Struct({
  kind: FsRecentKind,
  entries: Schema.Array(FsEntry),
  /** True when asking again with a bigger offset finds older items. */
  more: Schema.Boolean,
});
export type FsRecentResult = typeof FsRecentResult.Type;

export const FsDevice = Schema.Struct({
  deviceId: DeviceId,
  name: Schema.String,
  platform: Platform,
  /** Serving its files right now. */
  online: Schema.Boolean,
  /** Connected to the Mac, whether or not it shares its files. */
  connected: Schema.optionalKey(Schema.Boolean),
});
export type FsDevice = typeof FsDevice.Type;

export const FsDevicesResult = Schema.Struct({ devices: Schema.Array(FsDevice) });
export type FsDevicesResult = typeof FsDevicesResult.Type;

const RequestId = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(64));

export const FsServeInput = Schema.Struct({
  roots: Schema.Array(FsRoot),
  /** Set by builds that answer `Recent`. Older builds leave it out. */
  recent: Schema.optionalKey(Schema.Boolean),
});
export type FsServeInput = typeof FsServeInput.Type;

export const FsServeRequest = Schema.Union([
  Schema.TaggedStruct("List", { id: RequestId, path: FsPath, sort: FsSort, offset: NonNegativeInt, limit: PositiveInt }),
  Schema.TaggedStruct("Thumbs", { id: RequestId, paths: Schema.Array(FsPath) }),
  Schema.TaggedStruct("Send", { id: RequestId, paths: Schema.Array(FsPath), relay: Schema.NullOr(DeviceId) }),
  Schema.TaggedStruct("Recent", { id: RequestId, kind: FsRecentKind, offset: NonNegativeInt, limit: PositiveInt }),
]);
export type FsServeRequest = typeof FsServeRequest.Type;

export const FsServeResult = Schema.Union([
  Schema.TaggedStruct("List", { result: FsListResult }),
  Schema.TaggedStruct("Thumbs", { thumbs: Schema.Array(FsThumb) }),
  Schema.TaggedStruct("Send", { files: NonNegativeInt }),
  Schema.TaggedStruct("Recent", { result: FsRecentResult }),
]);
export type FsServeResult = typeof FsServeResult.Type;

export const FsReplyInput = Schema.Struct({
  id: RequestId,
  result: Schema.NullOr(FsServeResult),
  error: Schema.NullOr(Schema.String.check(Schema.isMaxLength(500))),
});
export type FsReplyInput = typeof FsReplyInput.Type;

export const FsPulled = Schema.Struct({ files: NonNegativeInt });
export type FsPulled = typeof FsPulled.Type;
