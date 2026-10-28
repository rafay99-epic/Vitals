import { describe, expect, test } from "bun:test";

import type { ErrorEvent } from "@sentry/react-native";

import { scrubEvent, scrubText } from "../src/lib/scrub.ts";

describe("scrubText", () => {
  test("drops links, Mac addresses, emails, paths and file names", () => {
    expect(scrubText("GET https://abduls-mac.tail1234.ts.net:7443/api/ws failed")).toBe("GET <url> failed");
    expect(scrubText("no route to 192.168.1.44:47810")).toBe("no route to <ip>");
    expect(scrubText("ENOENT: /storage/emulated/0/Download/Taxes 2026")).toBe("ENOENT: <path> 2026");
    expect(scrubText("could not open Invoice-March.pdf")).toBe("could not open <file>");
    expect(scrubText("signed in as abdul@rafay99.com")).toBe("signed in as <email>");
    expect(scrubText("pinging mac.tail1234.ts.net")).toBe("pinging <host>");
  });

  test("keeps what explains the bug", () => {
    const message = "TypeError: Cannot read property 'route' of undefined";
    expect(scrubText(message)).toBe(message);
  });
});

describe("scrubEvent", () => {
  test("strips the user, the device name and scrubs messages and breadcrumbs", () => {
    const event: ErrorEvent = {
      type: undefined,
      user: { id: "x" },
      server_name: "Abdul's iPhone",
      contexts: { device: { name: "Abdul's iPhone", model: "iPhone17,1" } },
      exception: { values: [{ type: "Error", value: "failed to read /Users/abdul/Documents/secret.txt" }] },
      breadcrumbs: [{ message: "opened photo.heic", data: { url: "https://mac.tail1234.ts.net/api" } }],
    };
    const scrubbed = scrubEvent(event);
    expect(scrubbed.user).toBeUndefined();
    expect(scrubbed.server_name).toBeUndefined();
    expect(scrubbed.contexts?.["device"]?.["name"]).toBeUndefined();
    expect(scrubbed.contexts?.["device"]?.["model"]).toBe("iPhone17,1");
    expect(scrubbed.exception?.values?.[0]?.value).toBe("failed to read <path>");
    expect(scrubbed.breadcrumbs?.[0]).toEqual({ message: "opened <file>", data: { url: "<url>" } });
  });
});
