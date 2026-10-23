import { describe, expect, test } from "bun:test";
import { type Connection, type ConnectionState, Store } from "@vitals/client-runtime";
import { Alert, Hello, PROTOCOL_VERSION } from "@vitals/contracts";
import * as Schema from "effect/Schema";

import { MacEvents } from "../src/state/events.ts";

const alert = Schema.decodeUnknownSync(Alert)({
  id: "alert-1",
  rule: "agentOverload",
  severity: "warning",
  summary: "25 agents running",
  raisedAt: 1,
  clearedAt: null,
  groups: [],
  plan: { actions: [], summary: "Lower priority" },
});

const hello = Schema.decodeUnknownSync(Hello)({
  protocol: PROTOCOL_VERSION,
  mac: null,
  keepAwake: null,
  lastEventSeq: 3,
  alerts: [alert],
  serverTime: 1,
  scopes: ["read"],
});

const ready = (latencyMs: number): ConnectionState => ({ _tag: "Ready", hello, since: 1, route: "lan", latencyMs });

const fakeConnection = (state: Store<ConnectionState>): Connection => ({
  state,
  call: () => new Promise(() => {}),
  watch: () => () => {},
  wake: () => {},
  suspend: () => {},
  dispose: () => {},
});

describe("MacEvents", () => {
  test("a heartbeat does not bring back alerts cleared after connecting", () => {
    const state = new Store<ConnectionState>({ _tag: "Idle" });
    const events = new MacEvents(fakeConnection(state), () => {});
    state.set(ready(20));
    expect(events.alerts.get()).toEqual([alert]);
    events.alerts.set([]);
    state.set(ready(35));
    expect(events.alerts.get()).toEqual([]);
    events.dispose();
  });
});
