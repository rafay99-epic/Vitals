import { describe, expect, test } from "bun:test";
import { Alert, LiveSample } from "@vitals/contracts";
import * as Schema from "effect/Schema";

import { bytes, sampleWord, stateWord } from "../src/state/vitals.ts";

const sample = (extra: Record<string, unknown>) => Schema.decodeUnknownSync(LiveSample)({ seq: 1, at: 1, ...extra });

const cpu = (overall: number) => ({ cpu: { overall, performance: overall, efficiency: overall, perCore: [] } });

const alert = Schema.decodeUnknownSync(Alert)({
  id: "alert-1",
  rule: "memoryPressure",
  severity: "critical",
  summary: "Memory pressure critical",
  raisedAt: 1,
  clearedAt: null,
  groups: [],
  plan: { actions: [], summary: "Pause idle emulators" },
});

const base = { alerts: [], signal: true, asleep: false, calmed: false } as const;

describe("sampleWord", () => {
  test("reads CPU bands", () => {
    expect(sampleWord(sample(cpu(12))).word).toBe("Resting.");
    expect(sampleWord(sample(cpu(50))).word).toBe("Elevated.");
    expect(sampleWord(sample(cpu(90))).word).toBe("Racing.");
  });

  test("thermal strain outranks CPU", () => {
    const hot = sample({ ...cpu(90), thermal: { cpuC: 95, gpuC: null, storageC: null, batteryC: null, state: "serious", sensors: [] } });
    expect(sampleWord(hot).word).toBe("Fever.");
  });

  test("keeps identity between equal samples so headers do not re-render", () => {
    expect(sampleWord(sample(cpu(10)))).toBe(sampleWord(sample(cpu(20))));
  });
});

describe("stateWord", () => {
  const resting = sampleWord(sample(cpu(10)));

  test("an open alarm wins", () => {
    expect(stateWord({ ...base, vitals: resting, alerts: [alert], signal: false })).toEqual({ word: "Pressure high.", tone: "alarmHigh" });
  });

  test("no signal beats sleep and vitals", () => {
    expect(stateWord({ ...base, vitals: resting, signal: false, asleep: true }).word).toBe("No signal.");
  });

  test("a fresh calm shows Calmed. over the vitals", () => {
    expect(stateWord({ ...base, vitals: resting, calmed: true }).word).toBe("Calmed.");
  });
});

describe("bytes", () => {
  test("splits value and unit and never invents zero", () => {
    expect(bytes(13_743_895_347)).toEqual({ value: "12.8", unit: "GB" });
    expect(bytes(null)).toEqual({ value: "--", unit: "" });
  });
});
