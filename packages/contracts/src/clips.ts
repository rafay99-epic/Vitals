import * as Schema from "effect/Schema";

import { DeviceId, EpochMs, NonNegativeInt, PositiveInt } from "./ids.ts";

/**
 * Clipboard history and drop: what the Mac copied, and what phones sent to it.
 * Clip bytes never cross the stdio bridge. The Mac app and the gateway share a `clips/` folder,
 * and phones move bytes through chunked RPCs that fit under the 1 MB frame limit.
 */
export const CLIP_LIMITS = {
  /** Raw bytes per `clips.read` / `clips.send.chunk` call. Base64 makes it about 683 KB on the wire. */
  chunkBytes: 512 * 1024,
  /** Text up to this size travels inline. Longer text is stored as a file and `text` holds a preview. */
  inlineText: 256 * 1024,
  /** Preview length for text stored as a file. */
  previewText: 4 * 1024,
  /** Base64 JPEG thumbnail cap, images only. */
  thumbChars: 48 * 1024,
  /** Largest single item either way. */
  itemBytes: 1024 * 1024 * 1024,
  /** Most clips one `clips.put` can place at once. */
  batch: 50,
  /** Clips in the first `Snapshot`. */
  snapshot: 200,
} as const;

/** Clip ids double as file names in the Mac's `clips/` folder, so they stay filename-safe. */
export const ClipId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{8,64}$/)).pipe(Schema.brand("ClipId"));
export type ClipId = typeof ClipId.Type;

export const UploadId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{8,64}$/)).pipe(Schema.brand("UploadId"));
export type UploadId = typeof UploadId.Type;

/** A bare file name inside `clips/`: `<id>.<ext>`. Never a path. */
export const ClipFileName = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{8,64}(\.[a-z0-9]{1,8}){1,2}$/));
export type ClipFileName = typeof ClipFileName.Type;

export const ClipKind = Schema.Literals(["text", "link", "image", "file", "folder"]);
export type ClipKind = typeof ClipKind.Type;

/** Kinds a phone can send. Folders only go Mac to phone (zipped on the Mac). */
export const SendKind = Schema.Literals(["text", "link", "image", "file"]);
export type SendKind = typeof SendKind.Type;

const Name = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(255));
const Mime = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(128));
const Sha256 = Schema.String.check(Schema.isPattern(/^[0-9a-f]{64}$/));
const Base64 = Schema.String.check(Schema.isMaxLength(Math.ceil(CLIP_LIMITS.chunkBytes / 3) * 4));

export const Clip = Schema.Struct({
  id: ClipId,
  kind: ClipKind,
  at: EpochMs,
  /** null when copied on the Mac, otherwise the phone that sent it. */
  deviceId: Schema.NullOr(DeviceId),
  /** The Mac app that was in front when it was copied, or the sending phone's name. */
  source: Schema.NullOr(Schema.String),
  /** Text and links. The whole text unless `truncated`, in which case `clips.read` has the rest. */
  text: Schema.NullOr(Schema.String),
  truncated: Schema.Boolean,
  name: Schema.NullOr(Schema.String),
  mime: Schema.NullOr(Schema.String),
  /** Download size. 0 for a folder that hasn't been zipped yet, and for inline text. */
  bytes: NonNegativeInt,
  /** Files inside a folder. */
  files: Schema.NullOr(NonNegativeInt),
  /** Base64 JPEG thumbnail for images. */
  thumb: Schema.NullOr(Schema.String),
  pinned: Schema.Boolean,
});
export type Clip = typeof Clip.Type;

export const ClipEvent = Schema.Union([
  /** First message on every watch, and again whenever history is turned on or off on the Mac. */
  Schema.TaggedStruct("Snapshot", {
    enabled: Schema.Boolean,
    /** Days the Mac keeps unpinned clips. null until the Mac has sent its policy. */
    keepDays: Schema.NullOr(PositiveInt),
    clips: Schema.Array(Clip),
  }),
  Schema.TaggedStruct("Added", { clip: Clip }),
  Schema.TaggedStruct("Updated", { clip: Clip }),
  Schema.TaggedStruct("Removed", { ids: Schema.Array(ClipId) }),
]);
export type ClipEvent = typeof ClipEvent.Type;

export const ClipsReadInput = Schema.Struct({ id: ClipId, offset: NonNegativeInt });
export type ClipsReadInput = typeof ClipsReadInput.Type;

export const ClipChunk = Schema.Struct({
  /** Base64 of at most `CLIP_LIMITS.chunkBytes` raw bytes. */
  data: Base64,
  offset: NonNegativeInt,
  total: NonNegativeInt,
  done: Schema.Boolean,
});
export type ClipChunk = typeof ClipChunk.Type;

export const ClipsPinInput = Schema.Struct({ id: ClipId, pinned: Schema.Boolean });
export type ClipsPinInput = typeof ClipsPinInput.Type;

export const ClipsRemoveInput = Schema.Struct({ id: ClipId });
export type ClipsRemoveInput = typeof ClipsRemoveInput.Type;

export const ClipSendBegin = Schema.Struct({
  kind: SendKind,
  name: Schema.NullOr(Name),
  mime: Schema.NullOr(Mime),
  /** 0 for text and links, which travel in `text` and need no chunks. */
  bytes: NonNegativeInt.check(Schema.isLessThanOrEqualTo(CLIP_LIMITS.itemBytes)),
  sha256: Schema.NullOr(Sha256),
  text: Schema.NullOr(Schema.String.check(Schema.isMaxLength(CLIP_LIMITS.inlineText))),
});
export type ClipSendBegin = typeof ClipSendBegin.Type;

export const ClipSendBegun = Schema.Struct({
  uploadId: UploadId,
  /** Set when nothing needs uploading (text and links): the clip is already stored. */
  clip: Schema.NullOr(Clip),
});
export type ClipSendBegun = typeof ClipSendBegun.Type;

export const ClipSendChunk = Schema.Struct({ uploadId: UploadId, offset: NonNegativeInt, data: Base64 });
export type ClipSendChunk = typeof ClipSendChunk.Type;

export const ClipSendFinish = Schema.Struct({ uploadId: UploadId });
export type ClipSendFinish = typeof ClipSendFinish.Type;

export const ClipDestination = Schema.Literals(["clipboard", "downloads"]);
export type ClipDestination = typeof ClipDestination.Type;

export const ClipsPutInput = Schema.Struct({
  ids: Schema.Array(ClipId).check(Schema.isMinLength(1), Schema.isMaxLength(CLIP_LIMITS.batch)),
  to: ClipDestination,
  /** Groups several files in one folder under Downloads. Ignored for the clipboard. */
  folder: Schema.NullOr(Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(120))),
});
export type ClipsPutInput = typeof ClipsPutInput.Type;

export const ClipsPutResult = Schema.Struct({ placed: NonNegativeInt });
export type ClipsPutResult = typeof ClipsPutResult.Type;

/* ---------- bridge (Mac app <-> gateway) ---------- */

/** What the Mac app reports for each copy. The gateway adds `deviceId: null` and `pinned: false`. */
export const MacClip = Schema.Struct({
  id: ClipId,
  kind: ClipKind,
  at: EpochMs,
  source: Schema.NullOr(Schema.String),
  text: Schema.NullOr(Schema.String),
  truncated: Schema.Boolean,
  name: Schema.NullOr(Schema.String),
  mime: Schema.NullOr(Schema.String),
  bytes: NonNegativeInt,
  files: Schema.NullOr(NonNegativeInt),
  thumb: Schema.NullOr(Schema.String),
  /** Bytes already written into `clips/` (images, long text). */
  stored: Schema.NullOr(ClipFileName),
  /** Absolute Mac path of a copied file or folder. Cloned or zipped into `clips/` on first download. */
  origin: Schema.NullOr(Schema.String),
  /** Sent on purpose (the send-clipboard shortcut): shown to phones even with history off. */
  pushed: Schema.optional(Schema.Boolean),
});
export type MacClip = typeof MacClip.Type;

export const ClipPolicy = Schema.Struct({
  enabled: Schema.Boolean,
  keepDays: PositiveInt.check(Schema.isLessThanOrEqualTo(90)),
});
export type ClipPolicy = typeof ClipPolicy.Type;

export const ClipStats = Schema.Struct({ clips: NonNegativeInt, pinned: NonNegativeInt, bytes: NonNegativeInt });
export type ClipStats = typeof ClipStats.Type;

/** One clip for the Mac app to place, already resolved by the gateway. */
export const ClipPlacement = Schema.Struct({
  kind: ClipKind,
  stored: Schema.NullOr(ClipFileName),
  text: Schema.NullOr(Schema.String),
  name: Schema.NullOr(Schema.String),
  mime: Schema.NullOr(Schema.String),
});
export type ClipPlacement = typeof ClipPlacement.Type;
