import { describe, expect, test } from "bun:test";

import { scrubAttributes, scrubRecord, scrubText } from "../src/scrub.ts";

describe("scrubText", () => {
  test("drops links, Mac addresses, emails, paths and file names", () => {
    expect(scrubText("GET https://abduls-mac.tail1234.ts.net:7443/api/ws failed")).toBe("GET <url> failed");
    expect(scrubText("no route to 192.168.1.44:47810")).toBe("no route to <ip>");
    expect(scrubText("ENOENT: /storage/emulated/0/Download/Taxes 2026")).toBe("ENOENT: <path> 2026");
    expect(scrubText("could not open Invoice-March.pdf")).toBe("could not open <file>");
    expect(scrubText("signed in as abdul@rafay99.com")).toBe("signed in as <email>");
    expect(scrubText("pinging mac.tail1234.ts.net")).toBe("pinging <host>");
    expect(scrubText("no answer from Abduls-MacBook-Pro.local:47810")).toBe("no answer from <host>:47810");
    expect(scrubText("route fe80::1c2b:3a4d%en0 failed")).toBe("route <ip> failed");
    expect(scrubText("The file “Passport Scan” couldn’t be opened")).toBe("The file “<name>” couldn’t be opened");
  });

  test("keeps what explains the bug", () => {
    const message = "TypeError: Cannot read property 'route' of undefined at 11:10:46";
    expect(scrubText(message)).toBe(message);
    expect(scrubText("client.app.fg")).toBe("client.app.fg");
    expect(scrubText("vitals-gateway@0.149-dev")).toBe("vitals-gateway@0.149-dev");
    expect(scrubText("com.syntaxlabtechnology.vitals.remote.dev@0.191+191")).toBe("com.syntaxlabtechnology.vitals.remote.dev@0.191+191");
  });
});

describe("scrubRecord", () => {
  test("scrubs strings nested in arrays and objects", () => {
    const data = { attempt: 2, failures: [{ kind: "lan", reason: "connect to 192.168.1.44:47810 failed" }] };
    expect(scrubRecord(data)).toEqual({ attempt: 2, failures: [{ kind: "lan", reason: "connect to <ip> failed" }] });
  });
});

describe("scrubAttributes", () => {
  test("keeps Sentry's own attributes and scrubs ours", () => {
    expect(scrubAttributes({ "sentry.release": "vitals-gateway@0.149-dev", "sentry.environment": "dev", reason: "no route to 192.168.1.44" })).toEqual({
      "sentry.release": "vitals-gateway@0.149-dev",
      "sentry.environment": "dev",
      reason: "no route to <ip>",
    });
  });
});
