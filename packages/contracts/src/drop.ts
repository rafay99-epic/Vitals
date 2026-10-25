import * as Schema from "effect/Schema";

import { FsPath } from "./fs.ts";
import { DeviceId, EpochMs, NonNegativeInt, PositiveInt } from "./ids.ts";

export const DROP_LIMITS = {
  partBytes: 16 * 1024 * 1024,
  files: 10_000,
  ticketMs: 60 * 60 * 1000,
  idleMs: 24 * 60 * 60 * 1000,
  clipboardBytes: 50 * 1024 * 1024,
} as const;

export const DROP_LAN_TLS_OFFSET = 10;

const IdPattern = /^[A-Za-z0-9-]{8,64}$/;

export const DropId = Schema.String.check(Schema.isPattern(IdPattern)).pipe(Schema.brand("DropId"));
export type DropId = typeof DropId.Type;

export const DropFileId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{1,64}$/)).pipe(Schema.brand("DropFileId"));
export type DropFileId = typeof DropFileId.Type;

const Name = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(255), Schema.isPattern(/^(?!\.\.?$)[^/\\\0]+$/));
const RelPath = Schema.String.check(
  Schema.isMinLength(1),
  Schema.isMaxLength(1024),
  Schema.isPattern(/^(?!\/)(?!.*(^|\/)\.\.(\/|$))[^\\\0]+$/),
);
const Mime = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(128));
const Sha256 = Schema.String.check(Schema.isPattern(/^[0-9a-f]{64}$/));

export const DropFileOffer = Schema.Struct({
  name: Name,
  path: Schema.NullOr(RelPath),
  size: NonNegativeInt,
  mime: Schema.NullOr(Mime),
  sha256: Schema.NullOr(Sha256),
});
export type DropFileOffer = typeof DropFileOffer.Type;

export const DropFile = Schema.Struct({
  id: DropFileId,
  name: Name,
  path: Schema.NullOr(RelPath),
  size: NonNegativeInt,
  mime: Schema.NullOr(Mime),
  sha256: Schema.NullOr(Sha256),
  done: NonNegativeInt,
});
export type DropFile = typeof DropFile.Type;

export const DropPeer = Schema.Union([
  Schema.TaggedStruct("Mac", { name: Schema.String }),
  Schema.TaggedStruct("Device", { deviceId: DeviceId, name: Schema.String }),
]);
export type DropPeer = typeof DropPeer.Type;

export const DropState = Schema.Literals(["asking", "waiting", "running", "paused", "done", "failed", "cancelled", "declined"]);
export type DropState = typeof DropState.Type;

export const Drop = Schema.Struct({
  id: DropId,
  from: DropPeer,
  to: DropPeer,
  files: Schema.Array(DropFile),
  bytes: NonNegativeInt,
  done: NonNegativeInt,
  state: DropState,
  route: Schema.NullOr(Schema.Literals(["lan", "tailnet"])),
  createdAt: EpochMs,
  updatedAt: EpochMs,
  error: Schema.NullOr(Schema.String),
});
export type Drop = typeof Drop.Type;

export const DropEvent = Schema.Union([
  Schema.TaggedStruct("Snapshot", { drops: Schema.Array(Drop) }),
  Schema.TaggedStruct("Changed", { drop: Drop }),
  Schema.TaggedStruct("Removed", { id: DropId }),
]);
export type DropEvent = typeof DropEvent.Type;

export const DropTicket = Schema.Struct({
  ticket: Schema.String.check(Schema.isMinLength(32), Schema.isMaxLength(128)),
  expiresAt: EpochMs,
});
export type DropTicket = typeof DropTicket.Type;

export const DropOfferInput = Schema.Struct({
  files: Schema.Array(DropFileOffer).check(Schema.isMinLength(1), Schema.isMaxLength(DROP_LIMITS.files)),
  dest: Schema.optionalKey(FsPath),
});
export type DropOfferInput = typeof DropOfferInput.Type;

export const DropOffered = Schema.Struct({ drop: Drop, ticket: DropTicket });
export type DropOffered = typeof DropOffered.Type;

export const DropIdInput = Schema.Struct({ id: DropId });
export type DropIdInput = typeof DropIdInput.Type;

export const DropReceivedInput = Schema.Struct({ id: DropId, fileId: DropFileId, sha256: Schema.NullOr(Sha256) });
export type DropReceivedInput = typeof DropReceivedInput.Type;

export const LanTls = Schema.Struct({
  port: PositiveInt,
  pin: Schema.String.check(Schema.isPattern(/^[A-Za-z0-9+/]{43}=$/)),
});
export type LanTls = typeof LanTls.Type;

export const DropPolicy = Schema.Struct({
  autoAccept: Schema.Boolean,
  askWeb: Schema.Boolean,
  maxBytes: PositiveInt,
});
export type DropPolicy = typeof DropPolicy.Type;

export const MacDropFile = Schema.Struct({
  name: Name,
  path: Schema.NullOr(RelPath),
  size: NonNegativeInt,
  mime: Schema.NullOr(Mime),
  origin: Schema.String.check(Schema.isMinLength(1)),
});
export type MacDropFile = typeof MacDropFile.Type;

export const ReceivedDropFile = Schema.Struct({
  stored: Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{8,64}\/[A-Za-z0-9-]{1,64}$/)),
  name: Name,
  path: Schema.NullOr(RelPath),
  size: NonNegativeInt,
});
export type ReceivedDropFile = typeof ReceivedDropFile.Type;
