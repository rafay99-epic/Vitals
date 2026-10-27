import { strFromU8 } from "fflate";

/** One file or folder listed in a zip's central directory. `header` is where its local header starts. */
export interface ZipEntry {
  readonly name: string;
  readonly folder: boolean;
  readonly size: number;
  readonly packed: number;
  readonly method: number;
  readonly encrypted: boolean;
  readonly header: number;
  readonly modifiedAt: number;
}

/** Where the central directory is and how big it is. */
export interface ZipDirectory {
  readonly offset: number;
  readonly size: number;
}

/** The longest a zip's tail can be: its end record plus the longest comment. */
export const ZIP_TAIL = 22 + 0xffff;

/** Local header bytes before the name and extra field. */
export const LOCAL_HEADER = 30;

const END = 0x06054b50;
const END64 = 0x06064b50;
const LOCATOR64 = 0x07064b50;
const CENTRAL = 0x02014b50;
const LOCAL = 0x04034b50;
const MAX32 = 0xffffffff;

const u16 = (bytes: Uint8Array, at: number): number => (bytes[at] ?? 0) | ((bytes[at + 1] ?? 0) << 8);
const u32 = (bytes: Uint8Array, at: number): number => u16(bytes, at) + u16(bytes, at + 2) * 0x10000;
const u64 = (bytes: Uint8Array, at: number): number => u32(bytes, at) + u32(bytes, at + 4) * 0x100000000;

const text = (bytes: Uint8Array): string => {
  try {
    return strFromU8(bytes);
  } catch {
    return strFromU8(bytes, true);
  }
};

/** MS-DOS date and time, as epoch ms in local time. */
const dosTime = (time: number, date: number): number =>
  new Date(1980 + (date >> 9), ((date >> 5) & 15) - 1, date & 31, time >> 11, (time >> 5) & 63, (time & 31) * 2).getTime();

/** Finds the central directory from a zip's last bytes. `start` is where `tail` begins in the file. Null when it isn't a zip. */
export const findDirectory = (tail: Uint8Array, start: number): ZipDirectory | null => {
  for (let at = tail.length - 22; at >= 0; at -= 1) {
    if (u32(tail, at) !== END) continue;
    const size = u32(tail, at + 12);
    const offset = u32(tail, at + 16);
    if (size !== MAX32 && offset !== MAX32) return { offset, size };
    const locator = at - 20;
    if (locator < 0 || u32(tail, locator) !== LOCATOR64) return null;
    const record = u64(tail, locator + 8) - start;
    if (record < 0 || u32(tail, record) !== END64) return null;
    return { offset: u64(tail, record + 48), size: u64(tail, record + 40) };
  }
  return null;
};

/** Sizes and offset a zip64 extra field overrides, in the order the format stores them. */
const zip64 = (extra: Uint8Array, size: number, packed: number, header: number) => {
  for (let at = 0; at + 4 <= extra.length; at += 4 + u16(extra, at + 2)) {
    if (u16(extra, at) !== 1) continue;
    let field = at + 4;
    const next = (value: number): number => {
      if (value !== MAX32) return value;
      const wide = u64(extra, field);
      field += 8;
      return wide;
    };
    return { size: next(size), packed: next(packed), header: next(header) };
  }
  return { size, packed, header };
};

/** Every entry in a central directory, in the order the zip lists them. */
export const readDirectory = (bytes: Uint8Array): ReadonlyArray<ZipEntry> => {
  const entries: Array<ZipEntry> = [];
  let at = 0;
  while (at + 46 <= bytes.length && u32(bytes, at) === CENTRAL) {
    const flags = u16(bytes, at + 8);
    const nameLength = u16(bytes, at + 28);
    const extraLength = u16(bytes, at + 30);
    const name = text(bytes.subarray(at + 46, at + 46 + nameLength));
    const wide = zip64(bytes.subarray(at + 46 + nameLength, at + 46 + nameLength + extraLength), u32(bytes, at + 24), u32(bytes, at + 20), u32(bytes, at + 42));
    entries.push({
      name,
      folder: name.endsWith("/"),
      size: wide.size,
      packed: wide.packed,
      method: u16(bytes, at + 10),
      encrypted: (flags & 1) === 1,
      header: wide.header,
      modifiedAt: dosTime(u16(bytes, at + 12), u16(bytes, at + 14)),
    });
    at += 46 + nameLength + extraLength + u16(bytes, at + 32);
  }
  return entries;
};

/** Where an entry's data starts, from the first `LOCAL_HEADER` bytes of its local header. */
export const dataStart = (local: Uint8Array, header: number): number => {
  if (u32(local, 0) !== LOCAL) throw new Error("This zip looks damaged");
  return header + LOCAL_HEADER + u16(local, 26) + u16(local, 28);
};

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

/** One level of a zip: the folders, then the files, directly inside `prefix` (`""` for the top, else ending in "/"). */
export const childrenOf = (entries: ReadonlyArray<ZipEntry>, prefix: string): ReadonlyArray<ZipEntry> => {
  const folders = new Map<string, ZipEntry>();
  const files: Array<ZipEntry> = [];
  for (const entry of entries) {
    if (!entry.name.startsWith(prefix) || entry.name.startsWith("__MACOSX/")) continue;
    const rest = entry.name.slice(prefix.length);
    const slash = rest.indexOf("/");
    if (rest === "" || rest.endsWith(".DS_Store")) continue;
    if (slash === -1) files.push(entry);
    else {
      const name = `${prefix}${rest.slice(0, slash + 1)}`;
      if (!folders.has(name)) folders.set(name, { name, folder: true, size: 0, packed: 0, method: 0, encrypted: false, header: 0, modifiedAt: entry.modifiedAt });
    }
  }
  const byName = (left: ZipEntry, right: ZipEntry) => collator.compare(left.name, right.name);
  return [...[...folders.values()].sort(byName), ...files.sort(byName)];
};

/** The last part of an entry's name, without a folder's trailing slash. */
export const baseName = (entry: ZipEntry): string => entry.name.replace(/\/$/, "").split("/").at(-1) ?? entry.name;
