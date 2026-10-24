import { constants } from "node:fs";
import { mkdir, open, readdir, rename, rm, stat, statfs } from "node:fs/promises";
import { join, resolve } from "node:path";

const WRITE_BUFFER = 1024 * 1024;

export type PartWrite = "ok" | "short" | "long" | "stopped" | "full" | "broken";

const isNoSpace = (error: unknown): boolean =>
  typeof error === "object" && error !== null && "code" in error && (error.code === "ENOSPC" || error.code === "EDQUOT");

export const hashFile = async (path: string, keepGoing: () => boolean = () => true): Promise<string | null> => {
  const hasher = new Bun.CryptoHasher("sha256");
  for await (const chunk of Bun.file(path).stream()) {
    if (!keepGoing()) return null;
    hasher.update(chunk);
  }
  return hasher.digest("hex");
};

export const dropFiles = (dataDir: string) => {
  const dir = resolve(dataDir, "drop");
  const folder = (dropId: string) => join(dir, dropId);
  const staged = (dropId: string, fileId: string) => join(dir, dropId, fileId);
  const part = (dropId: string, fileId: string) => join(dir, dropId, `${fileId}.part`);

  const writePart = async (body: ReadableStream<Uint8Array> | null, path: string, start: number, length: number, keepGoing: () => boolean): Promise<PartWrite> => {
    const handle = await open(path, constants.O_WRONLY | constants.O_CREAT, 0o600).catch((error: unknown): PartWrite => (isNoSpace(error) ? "full" : "broken"));
    if (typeof handle === "string") return handle;
    const buffer = Buffer.allocUnsafe(Math.min(WRITE_BUFFER, Math.max(1, length)));
    let filled = 0;
    let written = 0;
    const flush = async () => {
      let offset = 0;
      while (offset < filled) {
        const { bytesWritten } = await handle.write(buffer, offset, filled - offset, start + written + offset);
        offset += bytesWritten;
      }
      written += filled;
      filled = 0;
    };
    const reader = body?.getReader() ?? null;
    try {
      if (reader === null) return length === 0 ? "ok" : "short";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        if (written + filled + value.length > length) return "long";
        for (let taken = 0; taken < value.length; ) {
          const count = Math.min(value.length - taken, buffer.length - filled);
          buffer.set(value.subarray(taken, taken + count), filled);
          filled += count;
          taken += count;
          if (filled === buffer.length) await flush();
        }
        if (!keepGoing()) return "stopped";
      }
      await flush();
      return written === length ? "ok" : "short";
    } catch (error) {
      return isNoSpace(error) ? "full" : "broken";
    } finally {
      await reader?.cancel().catch(() => undefined);
      await handle.close().catch(() => undefined);
    }
  };

  return {
    dir,
    folder,
    staged,
    part,
    writePart,
    ensure: (dropId: string) => mkdir(folder(dropId), { recursive: true, mode: 0o700 }),
    publish: (dropId: string, fileId: string) => rename(part(dropId, fileId), staged(dropId, fileId)),
    createEmpty: async (dropId: string, fileId: string) => {
      await (await open(staged(dropId, fileId), "w", 0o600)).close();
    },
    removePart: (dropId: string, fileId: string) => rm(part(dropId, fileId), { force: true }).catch(() => undefined),
    removeDrop: (dropId: string) => rm(folder(dropId), { recursive: true, force: true }).catch(() => undefined),
    hasStaged: async (dropId: string): Promise<boolean> => {
      const entries = await readdir(folder(dropId)).catch(() => []);
      return entries.length > 0;
    },
    originSize: async (path: string): Promise<number | null> => {
      const info = await stat(path).catch(() => null);
      return info?.isFile() === true ? info.size : null;
    },
    freeBytes: async (): Promise<number | null> => {
      const info = await statfs(dataDir).catch(() => null);
      return info === null ? null : info.bavail * info.bsize;
    },
    prepare: async (known: ReadonlySet<string>): Promise<number> => {
      await mkdir(dir, { recursive: true, mode: 0o700 });
      let removed = 0;
      for (const entry of await readdir(dir)) {
        if (known.has(entry)) continue;
        await rm(join(dir, entry), { recursive: true, force: true });
        removed += 1;
      }
      return removed;
    },
  };
};

export type DropFiles = ReturnType<typeof dropFiles>;

export const partCount = (size: number, partBytes: number): number => Math.max(1, Math.ceil(size / partBytes));

export type PartRange = { readonly _tag: "Empty" } | { readonly _tag: "Part"; readonly index: number; readonly start: number; readonly length: number };

export const parseContentRange = (header: string | null, size: number, partBytes: number): PartRange | null => {
  const value = header?.trim() ?? "";
  if (value === "bytes */0") return size === 0 ? { _tag: "Empty" } : null;
  const match = /^bytes (\d{1,16})-(\d{1,16})\/(\d{1,16})$/.exec(value);
  if (match === null) return null;
  const [start, end, total] = [Number(match[1]), Number(match[2]), Number(match[3])];
  if (total !== size || start >= size || start % partBytes !== 0) return null;
  if (end - start + 1 !== Math.min(partBytes, size - start)) return null;
  return { _tag: "Part", index: start / partBytes, start, length: end - start + 1 };
};

export type ByteRange = { readonly _tag: "Whole" } | { readonly _tag: "Slice"; readonly start: number; readonly end: number };

export const parseRange = (header: string | null, size: number): ByteRange | null => {
  if (header === null) return { _tag: "Whole" };
  const match = /^bytes=(\d{1,16})-(\d{0,16})$/.exec(header.trim());
  if (match === null) return null;
  const start = Number(match[1]);
  const end = match[2] === "" ? size - 1 : Math.min(Number(match[2]), size - 1);
  if (start >= size || end < start) return null;
  return { _tag: "Slice", start, end };
};
