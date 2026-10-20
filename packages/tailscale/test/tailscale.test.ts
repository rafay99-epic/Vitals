import { describe, expect, test } from "bun:test";

import { httpsUrl, parseServeTarget, parseStatus, serveOn, status, type Runner } from "../src/index.ts";

const sample = JSON.stringify({
  BackendState: "Running",
  CurrentTailnet: { MagicDNSEnabled: true },
  Self: { DNSName: "mac.tail1234.ts.net.", UserID: 42 },
  User: { "42": { LoginName: "owner@" } },
});

describe("tailscale", () => {
  test("parses dns name and owner login", () => {
    expect(parseStatus(sample)).toEqual({
      running: true,
      dnsName: "mac.tail1234.ts.net",
      ownerLogin: "owner@",
      magicDns: true,
    });
  });

  test("a failing status call reports not running", async () => {
    const run: Runner = async () => ({ code: 1, stdout: "", stderr: "not running" });
    expect((await status(run)).running).toBe(false);
  });

  test("serve targets loopback only", async () => {
    const calls: Array<ReadonlyArray<string>> = [];
    const run: Runner = async (args) => {
      calls.push(args);
      return { code: 0, stdout: "", stderr: "" };
    };
    await serveOn(run, 7445, 47802);
    expect(calls[0]).toEqual(["serve", "--bg", "--https=7445", "http://127.0.0.1:47802"]);
    expect(httpsUrl("mac.ts.net", 7445)).toBe("https://mac.ts.net:7445");
  });

  test("reads the proxy target for one https port", () => {
    const serve = JSON.stringify({
      Web: {
        "mac.ts.net:443": { Handlers: { "/": { Proxy: "http://127.0.0.1:8040" } } },
        "mac.ts.net:7445": { Handlers: { "/": { Proxy: "http://127.0.0.1:47802" } } },
      },
    });
    expect(parseServeTarget(serve, 7445)).toBe("http://127.0.0.1:47802");
    expect(parseServeTarget(serve, 7444)).toBeNull();
    expect(parseServeTarget("", 7445)).toBeNull();
  });
});
