import { describe, expect, test } from "bun:test";

import { sentryDsn } from "../src/sentry.ts";

const projectOf = (dsn: string): string => dsn.split("/").at(-1) ?? "";

describe("sentryDsn", () => {
  test("only Stable reports to the prod projects", () => {
    expect(projectOf(sentryDsn("gateway", "stable"))).toBe("4512333741359104");
    expect(projectOf(sentryDsn("remote", "stable"))).toBe("4512333352861696");
  });

  test("Nightly and Dev report to the nightly projects", () => {
    for (const channel of ["nightly", "dev"] as const) {
      expect(projectOf(sentryDsn("gateway", channel))).toBe("4512333983383552");
      expect(projectOf(sentryDsn("remote", channel))).toBe("4512333983055872");
    }
  });
});
