import * as Schema from "effect/Schema";

import { EpochMs, NonNegativeInt, PositiveInt } from "./ids.ts";

export const FS_LIMITS = {
  page: 500,
  search: 200,
  thumbs: 24,
  pull: 10_000,
  thumbPixels: 192,
} as const;

export const FsPath = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(4096), Schema.isPattern(/^\/[^\0]*$/));
export type FsPath = typeof FsPath.Type;

export const FsName = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(255), Schema.isPattern(/^(?!\.\.?$)[^/\0]+$/));
export type FsName = typeof FsName.Type;

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

export const FsPlace = Schema.Literals(["home", "desktop", "documents", "downloads", "movies", "music", "pictures", "disk", "volume"]);
export type FsPlace = typeof FsPlace.Type;

export const FsRoot = Schema.Struct({
  label: Schema.String,
  path: FsPath,
  place: FsPlace,
});
export type FsRoot = typeof FsRoot.Type;

export const FsAccess = Schema.Literals(["folders", "everything"]);
export type FsAccess = typeof FsAccess.Type;

export const FsRootsResult = Schema.Struct({
  roots: Schema.Array(FsRoot),
  access: FsAccess,
  writable: Schema.Boolean,
});
export type FsRootsResult = typeof FsRootsResult.Type;

export const FsSort = Schema.Literals(["name", "date", "size"]);
export type FsSort = typeof FsSort.Type;

export const FsListInput = Schema.Struct({
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
  paths: Schema.Array(FsPath).check(Schema.isMinLength(1), Schema.isMaxLength(FS_LIMITS.pull)),
});
export type FsPathsInput = typeof FsPathsInput.Type;

export const FsThumbsInput = Schema.Struct({
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

export const FsRenameInput = Schema.Struct({ path: FsPath, name: FsName });
export type FsRenameInput = typeof FsRenameInput.Type;

export const FsFolderInput = Schema.Struct({ parent: FsPath, name: FsName });
export type FsFolderInput = typeof FsFolderInput.Type;

export const FsPathInput = Schema.Struct({ path: FsPath });
export type FsPathInput = typeof FsPathInput.Type;

export const FsTrashResult = Schema.Struct({ trashed: NonNegativeInt });
export type FsTrashResult = typeof FsTrashResult.Type;
