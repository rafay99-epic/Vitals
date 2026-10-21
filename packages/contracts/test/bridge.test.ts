import { describe, expect, test } from "bun:test";
import * as Schema from "effect/Schema";

import { FromApp, ToApp } from "../src/bridge.ts";
import fromAppFixture from "../fixtures/bridge/from-app.json" with { type: "json" };
import toAppFixture from "../fixtures/bridge/to-app.json" with { type: "json" };

const fromApp: ReadonlyArray<unknown> = fromAppFixture;
const toApp: ReadonlyArray<unknown> = toAppFixture;

const decodeFromApp = Schema.decodeUnknownSync(FromApp);
const decodeToApp = Schema.decodeUnknownSync(ToApp);
const encodeFromApp = Schema.encodeSync(FromApp);
const encodeToApp = Schema.encodeSync(ToApp);

describe("bridge fixtures", () => {
  test("every app message decodes and round-trips", () => {
    const encoded: ReadonlyArray<unknown> = fromApp.map((message) => encodeFromApp(decodeFromApp(message)));
    expect(encoded).toEqual(fromApp);
  });

  test("every gateway message decodes and round-trips", () => {
    const encoded: ReadonlyArray<unknown> = toApp.map((message) => encodeToApp(decodeToApp(message)));
    expect(encoded).toEqual(toApp);
  });

  test("unknown message types are rejected", () => {
    expect(() => decodeFromApp({ t: "nope" })).toThrow();
    expect(() => decodeToApp({ t: "cmd", id: "x", deviceId: "d", deviceName: "n", command: { _tag: "Format" } })).toThrow();
  });
});
