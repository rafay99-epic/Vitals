import * as Schema from "effect/Schema";

export const NonNegativeInt = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));
export const PositiveInt = Schema.Int.check(Schema.isGreaterThanOrEqualTo(1));
export const EpochMs = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));
export const Fraction = Schema.Number.check(Schema.isBetween({ minimum: 0, maximum: 1 }));
export const Percent = Schema.Number.check(Schema.isBetween({ minimum: 0, maximum: 100 }));

const NonEmpty = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(128));

export const DeviceId = NonEmpty.pipe(Schema.brand("DeviceId"));
export type DeviceId = typeof DeviceId.Type;

export const CommandId = NonEmpty.pipe(Schema.brand("CommandId"));
export type CommandId = typeof CommandId.Type;

export const ConnectionId = NonEmpty.pipe(Schema.brand("ConnectionId"));
export type ConnectionId = typeof ConnectionId.Type;

export const EventId = NonEmpty.pipe(Schema.brand("EventId"));
export type EventId = typeof EventId.Type;

export const AlertId = NonEmpty.pipe(Schema.brand("AlertId"));
export type AlertId = typeof AlertId.Type;

export const ProcessRef = Schema.Struct({
  pid: PositiveInt,
  startTimeMs: NonNegativeInt,
});
export type ProcessRef = typeof ProcessRef.Type;
