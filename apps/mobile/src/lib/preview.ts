import { fromBase64 } from "@vitals/app/lib/base64.ts";
import type { FsSource } from "@vitals/app/state/files.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import { FS_LIMITS, type FsEntry } from "@vitals/contracts";
import { openFile } from "@vitals/tailnet/drop";
import { Directory, File, FileMode, Paths } from "expo-file-system";
import { Inflate, strFromU8 } from "fflate";

import { toast } from "../ui/Toast.tsx";
import { SHEET_BYTES, type Workbook, workbookOf } from "./sheet.ts";
import { dataStart, findDirectory, LOCAL_HEADER, readDirectory, ZIP_TAIL, type ZipEntry } from "./zip.ts";

export type PreviewKind = "image" | "pdf" | "markdown" | "sheet" | "text" | "video" | "audio" | "zip" | "other";

const KINDS: ReadonlyArray<readonly [RegExp, PreviewKind]> = [
  [/\.(jpe?g|png|gif|webp|heic|heif|bmp|svg)$/i, "image"],
  [/\.pdf$/i, "pdf"],
  [/\.(mp4|m4v|mov|webm|mkv|3gp)$/i, "video"],
  [/\.(mp3|m4a|aac|wav|flac|ogg|oga|opus)$/i, "audio"],
  [/\.zip$/i, "zip"],
  [/\.(md|markdown|mdx)$/i, "markdown"],
  [/\.(xlsx|xlsm)$/i, "sheet"],
  [/\.(txt|text|tex|latex|bib|sty|cls|json|jsonl|ndjson|csv|tsv|log|xml|ya?ml|toml|ini|conf|cfg|env|sh|bash|zsh|fish|js|jsx|mjs|cjs|ts|tsx|py|rb|go|rs|swift|kt|kts|java|c|h|cc|cpp|hpp|m|mm|cs|php|html?|css|scss|sql|gradle|properties|srt|vtt|diff|patch)$/i, "text"],
];

/** Which viewer opens a file, by its name. */
export const previewKind = (name: string): PreviewKind => KINDS.find(([pattern]) => pattern.test(name))?.[1] ?? "other";

export const TOO_BIG = "Too big to preview. Transfer it instead.";

/** Text shows at most this much. */
export const TEXT_BYTES = 256 * 1024;

const IN_FLIGHT = 3;
const UNZIP_CHUNK = 256 * 1024;
/** Previews kept on the phone, newest first, before old ones are deleted. */
const KEEP_BYTES = 1024 * 1024 * 1024;

const ROOT = new Directory(Paths.cache, "previews");

/** A short, stable name for a cache key (53-bit cyrb53). */
const hash = (text: string): string => {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let index = 0; index < text.length; index += 1) {
    const code = text.charCodeAt(index);
    h1 = Math.imul(h1 ^ code, 2654435761);
    h2 = Math.imul(h2 ^ code, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(36);
};

/** One folder per device, path and modified time, holding the file under its own name. */
const folderFor = (entry: FsEntry, source: FsSource): Directory => new Directory(ROOT, hash(`${source.device ?? "mac"}\0${entry.path}\0${String(entry.modifiedAt)}`));

/** The cached copy of a file, or null when it isn't on this phone yet. */
export const cachedPreview = (entry: FsEntry, source: FsSource): File | null => {
  const file = new File(folderFor(entry, source), entry.name);
  return file.exists ? file : null;
};

/** Deletes the oldest previews once they take more than `KEEP_BYTES`. */
const prune = (): void => {
  try {
    if (!ROOT.exists) return;
    const folders = ROOT.list()
      .filter((item): item is Directory => item instanceof Directory)
      .map((folder) => ({ folder, info: folder.info() }))
      .sort((left, right) => (right.info.modificationTime ?? 0) - (left.info.modificationTime ?? 0));
    let kept = 0;
    for (const { folder, info } of folders) {
      kept += info.size ?? 0;
      if (kept > KEEP_BYTES) folder.delete();
    }
  } catch {
    // A cache that can't be tidied still works.
  }
};

export interface Progress {
  readonly done: number;
  readonly total: number;
}

/**
 * Copies a file from the Mac or another phone into this phone's cache, `IN_FLIGHT` chunks at a time, each
 * written to disk as it lands, so the file is never whole in memory. Reuses a cached copy. Resolves null
 * when `stopped()` turns true; the partial file is deleted.
 */
export const fetchPreview = async (remote: Remote, entry: FsEntry, source: FsSource, onProgress: (progress: Progress) => void, stopped: () => boolean): Promise<File | null> => {
  const cached = cachedPreview(entry, source);
  if (cached !== null) return cached;
  if (entry.size > FS_LIMITS.previewBytes) throw new Error(TOO_BIG);
  prune();
  const folder = folderFor(entry, source);
  folder.create({ intermediates: true, idempotent: true });
  const part = new File(folder, `${entry.name}.part`);
  part.create({ overwrite: true });
  const handle = part.open(FileMode.ReadWrite);
  const device = source.device ?? undefined;
  const chunk = FS_LIMITS.readChunk;
  const get = async (offset: number) => {
    const outcome = await remote.files.read(entry.path, offset, device);
    if (!outcome.ok) throw new Error(outcome.message);
    return outcome.value;
  };
  const put = (offset: number, data: string): number => {
    const bytes = fromBase64(data);
    handle.offset = offset;
    handle.writeBytesSync(bytes);
    return bytes.length;
  };
  let finished = false;
  let failed = false;
  const halted = () => failed || stopped();
  try {
    const first = await get(0);
    if (first.total > FS_LIMITS.previewBytes) throw new Error(TOO_BIG);
    if (stopped()) return null;
    let done = put(0, first.data);
    onProgress({ done, total: first.total });
    const offsets: Array<number> = [];
    if (!first.done) for (let offset = chunk; offset < first.total; offset += chunk) offsets.push(offset);
    let next = 0;
    const worker = async (): Promise<void> => {
      while (next < offsets.length && !halted()) {
        const offset = offsets[next] ?? 0;
        next += 1;
        try {
          const result = await get(offset);
          if (halted()) return;
          done += put(offset, result.data);
        } catch (cause) {
          failed = true;
          throw cause;
        }
        onProgress({ done, total: first.total });
      }
    };
    await Promise.all(Array.from({ length: IN_FLIGHT }, worker));
    if (stopped()) return null;
    handle.close();
    part.rename(entry.name);
    finished = true;
    return new File(folder, entry.name);
  } finally {
    if (!finished) {
      handle.close();
      folder.delete();
    }
  }
};

/** The start of a text file, cut at the last whole line when it's longer than `TEXT_BYTES`. */
export const readText = async (file: File): Promise<{ readonly text: string; readonly cut: boolean }> => {
  const handle = file.open(FileMode.ReadOnly);
  try {
    const cut = (handle.size ?? 0) > TEXT_BYTES;
    const bytes = await handle.readBytes(TEXT_BYTES);
    const end = cut ? bytes.lastIndexOf(10) : -1;
    const shown = end > 0 ? bytes.subarray(0, end) : bytes;
    let text: string;
    try {
      text = strFromU8(shown);
    } catch {
      text = strFromU8(shown, true);
    }
    return { text: text.replace(/\r\n?/g, "\n"), cut };
  } finally {
    handle.close();
  }
};

/** A cached .xlsx, unpacked in memory, so only up to `SHEET_BYTES`. */
export const readWorkbook = async (file: File): Promise<Workbook> => {
  const handle = file.open(FileMode.ReadOnly);
  try {
    const size = handle.size ?? 0;
    if (size > SHEET_BYTES) throw new Error("Too big to show here. Open it with another app.");
    return workbookOf(await handle.readBytes(size));
  } finally {
    handle.close();
  }
};

/** Every entry in a cached zip. Reads only its tail and central directory. */
export const listZip = async (file: File): Promise<ReadonlyArray<ZipEntry>> => {
  const handle = file.open(FileMode.ReadOnly);
  try {
    const size = handle.size ?? 0;
    const start = Math.max(0, size - ZIP_TAIL);
    handle.offset = start;
    const directory = findDirectory(await handle.readBytes(size - start), start);
    if (directory === null) throw new Error("This isn't a zip Vitals can read");
    handle.offset = directory.offset;
    return readDirectory(await handle.readBytes(directory.size));
  } finally {
    handle.close();
  }
};

/**
 * Unpacks one entry of a cached zip next to it, in chunks so the JS thread keeps breathing, and returns
 * it. Reuses an earlier unpack. Resolves null when `stopped()` turns true.
 */
export const unzipEntry = async (zip: File, entry: ZipEntry, stopped: () => boolean): Promise<File | null> => {
  if (entry.encrypted) throw new Error("This zip has a password. Transfer it instead.");
  if (entry.method !== 0 && entry.method !== 8) throw new Error("Vitals can't unpack this kind of zip. Transfer it instead.");
  if (entry.size > FS_LIMITS.previewBytes) throw new Error(TOO_BIG);
  const folder = new Directory(zip.parentDirectory, "unzipped", hash(entry.name));
  const name = entry.name.split("/").at(-1) ?? "file";
  const out = new File(folder, name);
  if (out.exists) return out;
  folder.create({ intermediates: true, idempotent: true });
  const part = new File(folder, `${name}.part`);
  part.create({ overwrite: true });
  const source = zip.open(FileMode.ReadOnly);
  const sink = part.open(FileMode.WriteOnly);
  let finished = false;
  try {
    source.offset = entry.header;
    source.offset = dataStart(await source.readBytes(LOCAL_HEADER), entry.header);
    const inflate = entry.method === 8 ? new Inflate((data) => sink.writeBytesSync(data)) : null;
    let left = entry.packed;
    while (left > 0) {
      if (stopped()) return null;
      const bytes = await source.readBytes(Math.min(UNZIP_CHUNK, left));
      if (bytes.length === 0) throw new Error("This zip looks damaged");
      left -= bytes.length;
      if (inflate === null) sink.writeBytesSync(bytes);
      else inflate.push(bytes, left === 0);
    }
    sink.close();
    part.rename(name);
    finished = true;
    return new File(folder, name);
  } finally {
    source.close();
    if (!finished) {
      sink.close();
      folder.delete();
    }
  }
};

/** Hands a cached file to another app: Android's chooser, or Quick Look on iPhone. */
export const openWith = (file: File): Promise<void> => openFile(file.uri, null).catch(() => toast.show("No app on this phone opens that file", { tone: "bad" }));
