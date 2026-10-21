import { describe, expect, test } from "bun:test";

import { formatBytes, formatPercent, newId, RingBuffer, uuidv7 } from "../src/index.ts";

describe("format", () => {
  test("bytes scale through units and reject junk", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(Number.NaN)).toBe("0 B");
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(1536)).toBe("1.5 KB");
    expect(formatBytes(1024 ** 5 * 3)).toBe("3072.0 TB");
    expect(formatBytes(0.5)).toBe("1 B");
    expect(formatPercent(null)).toBe("--");
  });
});

describe("RingBuffer", () => {
  test("keeps the newest values in order once full", () => {
    const buffer = new RingBuffer(3);
    for (const value of [1, 2, 3, 4, 5]) buffer.push(value);
    expect(buffer.length).toBe(3);
    expect(buffer.toArray()).toEqual([3, 4, 5]);
    expect(buffer.at(0)).toBe(3);
    expect(buffer.at(3)).toBeNaN();
    expect(buffer.at(-1)).toBeNaN();
    expect(new RingBuffer(4).at(0)).toBeNaN();
    expect(() => new RingBuffer(0)).toThrow(RangeError);
  });
});

describe("ids", () => {
  test("uuidv7 encodes time, version and variant", () => {
    const id = uuidv7(0x0189_abcd_ef01, new Uint8Array(16).fill(0xff));
    expect(id).toBe("0189abcd-ef01-7fff-bfff-ffffffffffff");
  });

  test("newId is unique and sorts by creation time", () => {
    const ids = Array.from({ length: 200 }, () => newId());
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids.every((id) => /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(id))).toBe(true);
    expect(newId().slice(0, 8) >= (ids[0] ?? "").slice(0, 8)).toBe(true);
  });
});
