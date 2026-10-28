import { describe, expect, test } from "bun:test";
import * as Schema from "effect/Schema";

import { DropFileOffer, LanTls } from "../src/drop.ts";

const offer = (path: string | null, name = "a.jpg") => Schema.decodeUnknownResult(DropFileOffer)({ name, path, size: 1, mime: null, sha256: null })._tag;

describe("drop contract", () => {
  test("relative paths stay inside the drop", () => {
    expect(offer("Trip/day 1/a.jpg")).toBe("Success");
    expect(offer(null)).toBe("Success");
    expect(offer("../etc/passwd")).toBe("Failure");
    expect(offer("Trip/../../x")).toBe("Failure");
    expect(offer("/Users/me/x")).toBe("Failure");
    expect(offer("a\\b")).toBe("Failure");
  });

  test("names are one path component", () => {
    expect(offer(null, "a/b.jpg")).toBe("Failure");
    expect(offer(null, "..")).toBe("Failure");
  });

  test("the LAN TLS pin is a base64 SHA-256", () => {
    expect(Schema.decodeUnknownResult(LanTls)({ port: 47822, pin: `${"A".repeat(43)}=` })._tag).toBe("Success");
    expect(Schema.decodeUnknownResult(LanTls)({ port: 47822, pin: "nope" })._tag).toBe("Failure");
  });
});
