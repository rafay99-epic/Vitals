import { describe, expect, test } from "bun:test";

import { scrubEvent } from "../src/scrub.ts";

describe("scrubEvent", () => {
  test("strips the user, the device name and scrubs messages and breadcrumbs", () => {
    const event = {
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
