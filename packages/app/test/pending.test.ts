import { describe, expect, test } from "bun:test";
import { isOverdue, type Pending, secondsLeft } from "../src/state/countdown.ts";

const shutDown = (deadlineAt: number): Pending => ({
  id: "cmd-1" as Pending["id"],
  kind: "ShutDown",
  deviceId: "device-1" as Pending["deviceId"],
  status: "pending",
  createdAt: 0,
  deadlineAt,
  finishedAt: null,
  error: null,
});

describe("pending countdowns", () => {
  test("a countdown that never got its last receipt stops showing after its deadline", () => {
    expect(secondsLeft(10_000, 10_000)).toBe("0 s");
    expect(isOverdue(shutDown(10_000), 15_000)).toBe(false);
    expect(isOverdue(shutDown(10_000), 21_000)).toBe(true);
  });
});
