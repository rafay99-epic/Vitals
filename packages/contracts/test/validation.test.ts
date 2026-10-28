import { describe, expect, test } from "bun:test";

import * as Schema from "effect/Schema";

import { GuardRule } from "../src/guard.ts";
import { HistoryRangeInput } from "../src/stats.ts";

const validHistory = Schema.is(HistoryRangeInput);
const validRule = Schema.is(GuardRule);

describe("input validation", () => {
  test("history ranges must move forward in time", () => {
    expect(validHistory({ series: ["cpu"], from: 1_000, to: 2_000, points: 60 })).toBe(true);
    expect(validHistory({ series: ["cpu"], from: 2_000, to: 2_000, points: 60 })).toBe(false);
    expect(validHistory({ series: ["cpu"], from: 3_000, to: 2_000, points: 60 })).toBe(false);
  });

  test("guard thresholds cannot be negative", () => {
    expect(validRule({ kind: "cpuSaturated", enabled: true, threshold: 90, holdSeconds: 60 })).toBe(true);
    expect(validRule({ kind: "cpuSaturated", enabled: true, threshold: -1, holdSeconds: 60 })).toBe(false);
  });
});
