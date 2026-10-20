import { ClientEvent } from "@vitals/contracts";
import * as Schema from "effect/Schema";

export interface Outbox {
  readonly push: (event: ClientEvent) => void;
  readonly take: (limit: number) => ReadonlyArray<ClientEvent>;
  readonly remove: (ids: ReadonlyArray<string>) => void;
}

const decode = Schema.decodeUnknownOption(Schema.fromJsonString(ClientEvent));

export const decodeEvent = (raw: string): ClientEvent | null => {
  const decoded = decode(raw);
  return decoded._tag === "Some" ? decoded.value : null;
};
