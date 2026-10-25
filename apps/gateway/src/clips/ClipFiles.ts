import { mkdir, readdir, rm, stat } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

import { ClipFileName } from "@vitals/contracts";
import * as Schema from "effect/Schema";

const isClipFileName = Schema.is(ClipFileName);

const MIME_EXTENSIONS: Readonly<Record<string, string>> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/gif": "gif",
  "image/heic": "heic",
  "image/heif": "heif",
  "image/webp": "webp",
  "image/tiff": "tiff",
  "image/svg+xml": "svg",
  "application/pdf": "pdf",
  "application/zip": "zip",
  "application/json": "json",
  "text/plain": "txt",
  "text/markdown": "md",
  "text/csv": "csv",
};

const EXTENSION = /^[a-z0-9]{1,8}$/;

/** A safe extension for an uploaded file: from its name, else its mime type, else `bin`. */
export const extensionFor = (name: string | null, mime: string | null): string => {
  const fromName = name?.match(/\.([^./\\]+)$/)?.[1]?.toLowerCase() ?? "";
  if (EXTENSION.test(fromName)) return fromName;
  const lowered = mime?.toLowerCase() ?? "";
  const known = MIME_EXTENSIONS[lowered];
  if (known !== undefined) return known;
  const subtype = (lowered.split("/")[1] ?? "").replace(/[^a-z0-9]/g, "").slice(0, 8);
  return EXTENSION.test(subtype) ? subtype : "bin";
};

export const hashFile = async (path: string): Promise<string> => {
  const hasher = new Bun.CryptoHasher("sha256");
  for await (const chunk of Bun.file(path).stream()) hasher.update(chunk);
  return hasher.digest("hex");
};

/**
 * The `clips/` folder the Mac app and the gateway share. Every path handed out resolves inside it:
 * stored files only by a bare `ClipFileName`, uploads only by the server-made upload id.
 */
export const clipFiles = (dataDir: string) => {
  const dir = resolve(dataDir, "clips");
  const incoming = join(dir, "incoming");

  const path = (name: string): string | null => {
    if (!isClipFileName(name)) return null;
    const full = resolve(dir, name);
    return dirname(full) === dir ? full : null;
  };

  const size = async (name: string): Promise<number | null> => {
    const full = path(name);
    if (full === null) return null;
    const info = await stat(full).catch(() => null);
    return info?.isFile() === true ? info.size : null;
  };

  return {
    dir,
    path,
    size,
    part: (uploadId: string): string => join(incoming, `${uploadId}.part`),

    /** Size and sha256 of a stored file, or null when it isn't there. */
    inspect: async (name: string): Promise<{ readonly bytes: number; readonly sha256: string } | null> => {
      const bytes = await size(name);
      const full = path(name);
      if (bytes === null || full === null) return null;
      const sha256 = await hashFile(full).catch(() => null);
      return sha256 === null ? null : { bytes, sha256 };
    },

    remove: async (name: string): Promise<void> => {
      const full = path(name);
      if (full !== null) await rm(full, { force: true }).catch(() => undefined);
    },

    removePart: async (uploadId: string): Promise<void> => {
      await rm(join(incoming, `${uploadId}.part`), { force: true }).catch(() => undefined);
    },

    /**
     * Startup: makes the folders, drops every half-finished upload (none survive a restart), and
     * deletes files no clip row points at. Files younger than `graceMs` are kept, since the Mac may
     * have just written one and not sent its `clip` message yet.
     */
    prepare: async (known: ReadonlySet<string>, graceMs: number): Promise<number> => {
      await mkdir(incoming, { recursive: true, mode: 0o700 });
      for (const entry of await readdir(incoming)) {
        if (entry.endsWith(".part")) await rm(join(incoming, entry), { force: true });
      }
      let removed = 0;
      const cutoff = Date.now() - graceMs;
      for (const entry of await readdir(dir, { withFileTypes: true })) {
        if (!entry.isFile() || known.has(entry.name)) continue;
        const full = join(dir, entry.name);
        const info = await stat(full).catch(() => null);
        if (info === null || info.mtimeMs > cutoff) continue;
        await rm(full, { force: true });
        removed += 1;
      }
      return removed;
    },
  };
};

export type ClipFiles = ReturnType<typeof clipFiles>;
