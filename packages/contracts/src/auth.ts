import * as Schema from "effect/Schema";

import { DeviceId, EpochMs, LanKey } from "./ids.ts";

export const Scope = Schema.Literals(["read", "operate", "destructive", "clipboard"]);
export type Scope = typeof Scope.Type;

export const DEFAULT_PAIRED_SCOPES: ReadonlyArray<Scope> = ["read", "operate"];

export const Platform = Schema.Literals(["android", "ios", "web"]);
export type Platform = typeof Platform.Type;

export const DeviceInfo = Schema.Struct({
  name: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(80)),
  platform: Platform,
  model: Schema.String.check(Schema.isMaxLength(80)),
  appVersion: Schema.String.check(Schema.isMaxLength(40)),
});
export type DeviceInfo = typeof DeviceInfo.Type;

export const PAIRING_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
export const PAIRING_CODE_LENGTH = 12;

export const PairingCode = Schema.String.check(
  Schema.isPattern(new RegExp(`^[${PAIRING_ALPHABET}]{${PAIRING_CODE_LENGTH}}$`)),
);

export const PairRequest = Schema.Struct({
  code: PairingCode,
  device: DeviceInfo,
  lanKey: Schema.optional(LanKey),
});
export type PairRequest = typeof PairRequest.Type;

export const PairResponse = Schema.Struct({
  deviceId: DeviceId,
  token: Schema.NullOr(Schema.String),
  scopes: Schema.Array(Scope),
  expiresAt: EpochMs,
});
export type PairResponse = typeof PairResponse.Type;

export const SessionInfo = Schema.Struct({
  deviceId: DeviceId,
  scopes: Schema.Array(Scope),
  pairedAt: EpochMs,
  expiresAt: EpochMs,
});
export type SessionInfo = typeof SessionInfo.Type;

export const Device = Schema.Struct({
  id: DeviceId,
  name: Schema.String,
  platform: Platform,
  model: Schema.String,
  appVersion: Schema.String,
  scopes: Schema.Array(Scope),
  createdAt: EpochMs,
  lastSeenAt: Schema.NullOr(EpochMs),
  revokedAt: Schema.NullOr(EpochMs),
  connected: Schema.Boolean,
});
export type Device = typeof Device.Type;

export class AuthError extends Schema.TaggedError<AuthError>()("AuthError", {
  message: Schema.String,
  requiredScope: Schema.NullOr(Scope),
}) {}

export class CommandRejected extends Schema.TaggedError<CommandRejected>()("CommandRejected", {
  message: Schema.String,
}) {}

export class Unavailable extends Schema.TaggedError<Unavailable>()("Unavailable", {
  message: Schema.String,
}) {}
