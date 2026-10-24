import * as Schema from "effect/Schema";

import { DeviceInfo, Scope } from "./auth.ts";
import { LanTls } from "./drop.ts";
import { DeviceId, EpochMs, LanKey, PositiveInt } from "./ids.ts";

export const LAN_PORTS = { stable: 47810, nightly: 47811, dev: 47812 } as const;

export const LAN_SERVICE_TYPE = "_vitals._tcp";

export const LAN_PROLOGUE = "vitals-lan-v1";

export const PAIR_REQUEST_TTL_MS = 120_000;

export const LanEndpoint = Schema.Struct({
  host: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(64)),
  port: PositiveInt,
});
export type LanEndpoint = typeof LanEndpoint.Type;

export const MacRoutes = Schema.Struct({
  key: LanKey,
  lan: Schema.Array(LanEndpoint),
  tailnet: Schema.NullOr(Schema.String),
  owner: Schema.optional(Schema.NullOr(Schema.String)),
  tls: Schema.optional(LanTls),
});
export type MacRoutes = typeof MacRoutes.Type;

export const LanAdvert = Schema.Struct({
  protocol: Schema.Number,
  name: Schema.String,
  key: LanKey,
  channel: Schema.Literals(["stable", "nightly", "dev"]),
});
export type LanAdvert = typeof LanAdvert.Type;

export const LanOpen = Schema.Union([
  Schema.Struct({ t: Schema.Literal("connect"), v: Schema.Number, client: Schema.String.check(Schema.isMaxLength(40)) }),
  Schema.Struct({ t: Schema.Literal("pair"), v: Schema.Number, device: DeviceInfo }),
]);
export type LanOpen = typeof LanOpen.Type;

export const LanAccept = Schema.Union([
  Schema.Struct({ t: Schema.Literal("ready") }),
  Schema.Struct({ t: Schema.Literal("waiting"), expiresAt: EpochMs }),
  Schema.Struct({ t: Schema.Literal("unknown") }),
  Schema.Struct({ t: Schema.Literal("busy") }),
  Schema.Struct({ t: Schema.Literal("incompatible"), protocol: Schema.Number }),
]);
export type LanAccept = typeof LanAccept.Type;

export const LanPairResult = Schema.Union([
  Schema.Struct({
    t: Schema.Literal("paired"),
    deviceId: DeviceId,
    token: Schema.String,
    scopes: Schema.Array(Scope),
    expiresAt: EpochMs,
    routes: MacRoutes,
  }),
  Schema.Struct({ t: Schema.Literal("denied") }),
  Schema.Struct({ t: Schema.Literal("expired") }),
]);
export type LanPairResult = typeof LanPairResult.Type;

export const PairPrompt = Schema.Struct({
  id: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(64)),
  device: DeviceInfo,
  code: Schema.String.check(Schema.isPattern(/^\d{4}$/)),
  address: Schema.String,
  expiresAt: EpochMs,
});
export type PairPrompt = typeof PairPrompt.Type;
