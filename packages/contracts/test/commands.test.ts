import { describe, expect, test } from "bun:test";

import type { Command } from "../src/commands.ts";
import { requiredScope } from "../src/scopes.ts";

const run = (command: Command) => requiredScope("command.run", { command });
const target = { pid: 10, startTimeMs: 1 };

describe("command scopes", () => {
  test("reversible commands need operate", () => {
    expect(run({ _tag: "Sleep", graceSeconds: 0 })).toBe("operate");
    expect(run({ _tag: "Processes", actions: [{ target, action: "pause" }] })).toBe("operate");
  });

  test("irreversible commands need destructive", () => {
    expect(run({ _tag: "ShutDown", graceSeconds: 10 })).toBe("destructive");
    expect(run({ _tag: "Processes", actions: [{ target, action: "throttle" }, { target, action: "kill" }] })).toBe("destructive");
    expect(run({ _tag: "StopEmulator", kind: "ios", id: "x" })).toBe("destructive");
  });

  test("a malformed payload fails closed", () => {
    expect(requiredScope("command.run", null)).toBe("destructive");
    expect(requiredScope("clipboard.get", {})).toBe("clipboard");
  });
});
