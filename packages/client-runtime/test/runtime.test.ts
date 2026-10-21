import { describe, expect, test } from "bun:test";

import { SessionInfo } from "@vitals/contracts";
import * as Schema from "effect/Schema";

import { fetchOpenAlerts, fetchSession, parsePairingDeepLink, parsePairingUrl, retryDelayMs, RETRY_MAX_DELAY_MS, unpair } from "../src/index.ts";

type Call = { readonly url: string; readonly init: RequestInit | undefined };

const fakeFetch = (respond: (call: Call) => Response | Promise<Response>) => {
  const calls: Array<Call> = [];
  const impl = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const call = { url: String(input), init };
    calls.push(call);
    return respond(call);
  }) as typeof globalThis.fetch;
  return { impl, calls };
};

const session = Schema.decodeUnknownSync(SessionInfo)({
  deviceId: "device-1",
  scopes: ["read", "operate"],
  pairedAt: 1_700_000_000_000,
  expiresAt: 1_800_000_000_000,
});

describe("backoff", () => {
  test("delay stays within equal-jitter bounds and caps at five minutes", () => {
    expect(retryDelayMs(0, 0)).toBe(1_000);
    expect(retryDelayMs(0, 1)).toBe(2_000);
    expect(retryDelayMs(3, 0.5)).toBe(12_000);
    expect(retryDelayMs(30, 1)).toBe(RETRY_MAX_DELAY_MS);
  });
});

describe("pairing links", () => {
  test("reads the code from the hash and normalizes it", () => {
    expect(parsePairingUrl("https://mac.ts.net:7445/pair#code=abcd-efgh-jklm")).toEqual({
      baseUrl: "https://mac.ts.net:7445",
      code: "ABCDEFGHJKLM",
      macKey: null,
    });
    const key = "q".repeat(43);
    expect(parsePairingUrl(`https://mac.ts.net:7445/pair#code=ABCDEFGHJKLM&key=${key}`)?.macKey).toBe(key);
    expect(parsePairingUrl("https://mac.ts.net:7445/pair#code=ABCDEFGHJKLM&key=short")?.macKey).toBeNull();
    expect(parsePairingUrl("https://mac.ts.net/pair#code=ABCD")).toBeNull();
    expect(parsePairingUrl("ftp://mac.ts.net/pair#code=ABCDEFGHJKLM")).toBeNull();
    expect(parsePairingUrl("not a url")).toBeNull();
  });

  test("app deep links carry a full pairing link", () => {
    const link = encodeURIComponent("https://mac.ts.net:7445/pair#code=ABCDEFGHJKLM");
    expect(parsePairingDeepLink(`vitals-preview://pair?link=${link}`)).toEqual({ baseUrl: "https://mac.ts.net:7445", code: "ABCDEFGHJKLM", macKey: null });
    expect(parsePairingDeepLink(`vitals://other?link=${link}`)).toBeNull();
    expect(parsePairingDeepLink("vitals://pair")).toBeNull();
    expect(parsePairingDeepLink("https://mac.ts.net:7445/pair#code=ABCDEFGHJKLM")).toBeNull();
  });
});

describe("account", () => {
  test("session lookup tells paired, unpaired and unreachable apart", async () => {
    const paired = fakeFetch(() => Response.json(session));
    expect(await fetchSession("https://mac", "tok", paired.impl)).toEqual({ _tag: "Paired", session });
    expect(paired.calls[0]?.init?.headers).toEqual({ authorization: "Bearer tok" });

    const cookieOnly = fakeFetch(() => new Response(null, { status: 204 }));
    expect(await fetchSession("https://mac", null, cookieOnly.impl)).toEqual({ _tag: "Unpaired" });
    expect(cookieOnly.calls[0]?.init?.headers).toEqual({});

    expect(await fetchSession("https://mac", null, fakeFetch(() => new Response(null, { status: 502 })).impl)).toEqual({ _tag: "Unreachable" });
    expect(await fetchSession("https://mac", null, fakeFetch(() => Response.json({ nope: true })).impl)).toEqual({ _tag: "Unreachable" });
    const offline = fakeFetch(() => Promise.reject(new TypeError("offline")));
    expect(await fetchSession("https://mac", null, offline.impl)).toEqual({ _tag: "Unreachable" });
  });

  test("unpair treats an already revoked session as done", async () => {
    expect(await unpair("https://mac", "tok", fakeFetch(() => new Response(null, { status: 401 })).impl)).toBe(true);
    expect(await unpair("https://mac", "tok", fakeFetch(() => Promise.reject(new TypeError("offline"))).impl)).toBe(false);
  });

  test("open alerts are validated before use", async () => {
    const good = fakeFetch(() => Response.json({ lastSeq: 4, alerts: [] }));
    expect(await fetchOpenAlerts("https://mac", "tok", 2, good.impl)).toEqual({ lastSeq: 4, alerts: [] });
    expect(good.calls[0]?.url).toBe("https://mac/api/alerts?after=2");
    expect(await fetchOpenAlerts("https://mac", "tok", 0, fakeFetch(() => Response.json({ lastSeq: -1, alerts: [] })).impl)).toBeNull();
  });
});
