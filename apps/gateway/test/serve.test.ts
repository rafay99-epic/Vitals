import { describe, expect, test } from "bun:test";

import { setupStep } from "../src/tailscale/Serve.ts";

const status = (overrides: Partial<Parameters<typeof setupStep>[0]>) => ({
  backendState: "Running",
  running: true,
  dnsName: "mac.tail1234.ts.net",
  ownerLogin: "owner@",
  magicDns: true,
  ...overrides,
});

describe("Tailscale setup step", () => {
  test("walks the steps in the order the Mac's setup sheet shows them", () => {
    expect(setupStep(status({ backendState: null, running: false }), false)).toBe("start");
    expect(setupStep(status({ backendState: "NeedsLogin", running: false }), false)).toBe("signin");
    expect(setupStep(status({ magicDns: false }), false)).toBe("magicdns");
    expect(setupStep(status({ dnsName: null }), false)).toBe("magicdns");
    expect(setupStep(status({}), false)).toBe("https");
    expect(setupStep(status({}), true)).toBe("ready");
  });
});
