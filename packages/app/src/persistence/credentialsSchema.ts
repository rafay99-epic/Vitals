import { DeviceId, Scope } from "@vitals/contracts";
import * as Schema from "effect/Schema";

export const Credentials = Schema.Struct({
  baseUrl: Schema.String,
  token: Schema.NullOr(Schema.String),
  deviceId: DeviceId,
  scopes: Schema.Array(Scope),
  pairedAt: Schema.Number,
});
export type Credentials = typeof Credentials.Type;

const decode = Schema.decodeUnknownOption(Schema.fromJsonString(Credentials));

export const decodeCredentials = (raw: string | null): Credentials | null => {
  if (raw === null) return null;
  const decoded = decode(raw);
  return decoded._tag === "Some" ? decoded.value : null;
};
