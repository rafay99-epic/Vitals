import * as Schema from "effect/Schema";

import { EpochMs, EventId, NonNegativeInt } from "./ids.ts";

export const ActivitySource = Schema.Literals(["gateway", "desktop", "client"]);
export type ActivitySource = typeof ActivitySource.Type;

export const ActivityLevel = Schema.Literals(["debug", "info", "warn", "error"]);
export type ActivityLevel = typeof ActivityLevel.Type;

const Kind = Schema.String.check(Schema.isPattern(/^[a-z][a-zA-Z]*(\.[a-zA-Z]+)+$/), Schema.isMaxLength(64));

export const JsonValue = Schema.Unknown;

export const ClientEvent = Schema.Struct({
  eventId: EventId,
  at: EpochMs,
  level: ActivityLevel,
  kind: Kind,
  data: Schema.Record(Schema.String, JsonValue),
});
export type ClientEvent = typeof ClientEvent.Type;

export const ActivityIngestInput = Schema.Struct({
  events: Schema.Array(ClientEvent).check(Schema.isMaxLength(200)),
});
export type ActivityIngestInput = typeof ActivityIngestInput.Type;

export const ActivityIngestResult = Schema.Struct({ accepted: Schema.Int });
export type ActivityIngestResult = typeof ActivityIngestResult.Type;

export const ActivityClearResult = Schema.Struct({ removed: NonNegativeInt });
export type ActivityClearResult = typeof ActivityClearResult.Type;
