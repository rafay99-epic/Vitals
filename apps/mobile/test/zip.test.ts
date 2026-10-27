import { describe, expect, test } from "bun:test";
import { inflateSync, strFromU8, strToU8, zipSync } from "fflate";

import { baseName, childrenOf, dataStart, findDirectory, LOCAL_HEADER, readDirectory, ZIP_TAIL } from "../src/lib/zip.ts";

const archive = zipSync({
  "README.md": strToU8("# Readme\n"),
  "docs/notes.txt": [strToU8("note ".repeat(2_000)), { level: 9 }],
  "docs/raw.bin": [new Uint8Array([1, 2, 3, 4]), { level: 0 }],
  "pics/photo.jpg": new Uint8Array(64),
  "__MACOSX/docs/._notes.txt": new Uint8Array(4),
  "docs/.DS_Store": new Uint8Array(4),
});

const listing = () => {
  const start = Math.max(0, archive.length - ZIP_TAIL);
  const directory = findDirectory(archive.subarray(start), start);
  if (directory === null) throw new Error("no directory");
  return readDirectory(archive.subarray(directory.offset, directory.offset + directory.size));
};

/** Reads one entry the way the phone does: its local header, then its data. */
const unpack = (name: string): Uint8Array => {
  const entry = listing().find((item) => item.name === name);
  if (entry === undefined) throw new Error(`no ${name}`);
  const start = dataStart(archive.subarray(entry.header, entry.header + LOCAL_HEADER), entry.header);
  const data = archive.subarray(start, start + entry.packed);
  return entry.method === 8 ? inflateSync(data) : data;
};

describe("zip", () => {
  test("lists every entry with its real size", () => {
    const entries = listing();
    expect(entries.map((entry) => entry.name).sort()).toEqual(["README.md", "__MACOSX/docs/._notes.txt", "docs/.DS_Store", "docs/notes.txt", "docs/raw.bin", "pics/photo.jpg"]);
    expect(entries.find((entry) => entry.name === "docs/notes.txt")?.size).toBe(10_000);
  });

  test("unpacks deflated and stored entries", () => {
    expect(strFromU8(unpack("docs/notes.txt"))).toBe("note ".repeat(2_000));
    expect([...unpack("docs/raw.bin")]).toEqual([1, 2, 3, 4]);
  });

  test("shows one level at a time, folders first, without Mac clutter", () => {
    expect(childrenOf(listing(), "").map(baseName)).toEqual(["docs", "pics", "README.md"]);
    expect(childrenOf(listing(), "docs/").map(baseName)).toEqual(["notes.txt", "raw.bin"]);
  });

  test("says when a file isn't a zip", () => {
    expect(findDirectory(strToU8("not a zip at all"), 0)).toBeNull();
  });
});
