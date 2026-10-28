import { describe, expect, test } from "bun:test";

import { fixFor, freshRun, reportOf, withStep } from "../src/lib/checkModel.ts";

const base = freshRun(Date.UTC(2026, 9, 28, 17, 52));

describe("connection check", () => {
  test("nothing failed means nothing to fix", () => {
    expect(fixFor(withStep(base, "network", "ok"))).toBeNull();
  });

  test("the first Wi-Fi failure picks the fix, and a VPN changes it", () => {
    const silent = withStep(withStep(base, "found", "ok"), "answers", "failed", "No answer in 3 s", "no-answer");
    expect(fixFor(silent)?.title).toBe("The Mac is on this Wi-Fi but doesn't answer.");
    expect(fixFor({ ...silent, vpn: true })?.title).toBe("A VPN is sending the traffic away.");
    expect(fixFor(withStep(base, "knows", "failed", "the Mac answered unknown", "unknown-phone"))?.action).toBe("pair");
  });

  test("on cellular a broken Tailscale is what to fix", () => {
    const cellular = withStep(base, "network", "failed", "On cellular", "cellular");
    expect(fixFor(cellular)?.title).toBe("Join the Mac's Wi-Fi.");
    expect(fixFor(withStep(cellular, "tailscale", "failed", "Needs a sign-in", "tailscale-login"))?.title).toBe("Sign in to built-in Tailscale.");
  });

  test("the report lists the build, each step, the fix and the journal", () => {
    const run = withStep(withStep(base, "network", "ok"), "answers", "failed", "No answer in 3 s", "no-answer");
    const report = reportOf(run, "0.181", [{ at: Date.UTC(2026, 9, 28, 17, 49), kind: "pair", text: "Wi-Fi pairing unreachable" }]).split("\n");
    expect(report[0]).toBe("Vitals Remote 0.181, checked 2026-10-28 17:52:00 UTC");
    expect(report).toContain("ok On Wi-Fi");
    expect(report).toContain("XX The Mac answers: No answer in 3 s");
    expect(report.some((line) => line.startsWith("Fix: The Mac is on this Wi-Fi"))).toBe(true);
    expect(report.at(-1)).toBe("2026-10-28 17:49:00 pair Wi-Fi pairing unreachable");
  });
});
