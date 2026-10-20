import type { ClientEvent } from "@vitals/contracts";

import type { Outbox } from "./outboxShared.ts";

const CAP = 2_000;

export const openOutbox = (): Outbox => {
  let events: Array<ClientEvent> = [];
  return {
    push: (event) => {
      events = [...events, event].slice(-CAP);
    },
    take: (limit) => events.slice(0, limit),
    remove: (ids) => {
      const drop = new Set(ids);
      events = events.filter((event) => !drop.has(event.eventId));
    },
  };
};
