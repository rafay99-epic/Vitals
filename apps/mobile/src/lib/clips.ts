import { clipTitle, fileNameOf, isLink } from "@vitals/app/features/clips/format.ts";
import { fromBase64, toBase64 } from "@vitals/app/lib/base64.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import type { ByteSink, ByteSource, Outgoing } from "@vitals/app/state/transfer.ts";
import type { Clip, ClipDestination, SendKind } from "@vitals/contracts";
import * as Clipboard from "expo-clipboard";
import * as DocumentPicker from "expo-document-picker";
import { Directory, File, FileMode, Paths } from "expo-file-system";
import * as ImagePicker from "expo-image-picker";
import * as MediaLibrary from "expo-media-library";
import * as Sharing from "expo-sharing";

import { toast } from "../ui/Toast.tsx";
import { send } from "./remote.ts";

/** Hashing happens on device, natively. Past this size it costs more than the check is worth. */
const HASH_UP_TO = 100 * 1024 * 1024;

/** Downloads land here, one folder per clip so shared files keep their real names. */
const CACHE = new Directory(Paths.cache, "clips");
let cacheCleared = false;

/** One cursor per file handle, so reads and writes take turns. */
const serial = () => {
  let tail: Promise<unknown> = Promise.resolve();
  return <A>(job: () => Promise<A>): Promise<A> => {
    const run = tail.then(job);
    tail = run.catch(() => undefined);
    return run;
  };
};

const safeName = (name: string): string => name.replace(/[/\\:\0]/g, "-").slice(0, 200) || "clip";

/** Reads a local or content URI a chunk at a time. Opened when the send starts, closed when it ends. */
const fileSource = (uri: string): ByteSource => {
  const handle = new File(uri).open(FileMode.ReadOnly);
  const turn = serial();
  return {
    size: handle.size ?? 0,
    read: (offset, length) =>
      turn(async () => {
        handle.offset = offset;
        return toBase64(await handle.readBytes(length));
      }),
    close: () => handle.close(),
  };
};

/** A cache file that takes chunks in any order. Never holds the whole file in memory. */
const cacheSink = (clip: Clip): { readonly file: File; readonly sink: ByteSink } => {
  if (!cacheCleared) {
    cacheCleared = true;
    if (CACHE.exists) CACHE.delete();
  }
  const folder = new Directory(CACHE, clip.id);
  folder.create({ intermediates: true, idempotent: true });
  const file = new File(folder, safeName(fileNameOf(clip)));
  file.create({ overwrite: true });
  const handle = file.open(FileMode.WriteOnly);
  const turn = serial();
  return {
    file,
    sink: {
      write: (offset, base64) =>
        turn(async () => {
          handle.offset = offset;
          await handle.writeBytes(fromBase64(base64));
        }),
      finish: () => turn(async () => handle.close()),
      abort: () =>
        void turn(async () => {
          handle.close();
          if (folder.exists) folder.delete();
        }),
    },
  };
};

/** Downloads a clip to the cache. Progress shows in the transfer strip. Null if cancelled or failed. */
const downloadClip = async (remote: Remote, clip: Clip): Promise<File | null> => {
  const { file, sink } = cacheSink(clip);
  const done = await remote.clips.fetch(`Getting ${clipTitle(clip)}`, clip, sink).result;
  return done === null ? null : file;
};

/** The whole text of a clip. Long text lives in a file on the Mac, with only a preview inline. */
const fullText = async (remote: Remote, clip: Clip): Promise<string | null> => {
  if (!clip.truncated) return clip.text;
  const file = await downloadClip(remote, clip);
  return file === null ? null : file.text();
};

/** Copies a text, link or image clip onto this phone's clipboard. */
export const copyToPhone = async (remote: Remote, clip: Clip): Promise<boolean> => {
  if (clip.kind === "image") {
    const file = await downloadClip(remote, clip);
    if (file === null) return false;
    await Clipboard.setImageAsync(await file.base64());
    return true;
  }
  const text = await fullText(remote, clip);
  if (text === null) return false;
  await Clipboard.setStringAsync(text);
  return true;
};

export const saveToPhotos = async (remote: Remote, clip: Clip): Promise<void> => {
  const permission = await MediaLibrary.requestPermissionsAsync(true, ["photo"]);
  if (!permission.granted) return toast.show("Vitals can't save to Photos. Allow it in Settings.", { tone: "bad" });
  const file = await downloadClip(remote, clip);
  if (file === null) return;
  await MediaLibrary.Asset.create(file.uri);
  toast.show("Saved to Photos");
};

/** Asks for a folder first, so nothing downloads if the person backs out. */
export const saveToFolder = async (remote: Remote, clip: Clip): Promise<void> => {
  const folder = await Directory.pickDirectoryAsync().catch(() => null);
  if (folder === null) return;
  const file = await downloadClip(remote, clip);
  if (file === null) return;
  const name = safeName(fileNameOf(clip));
  await file.copy(folder.createFile(name, clip.kind === "folder" ? "application/zip" : clip.mime), { overwrite: true });
  toast.show(`${name} saved`);
};

export const shareClip = async (remote: Remote, clip: Clip): Promise<void> => {
  const file = await downloadClip(remote, clip);
  if (file === null) return;
  await Sharing.shareAsync(file.uri, { mimeType: clip.kind === "folder" ? "application/zip" : (clip.mime ?? "application/octet-stream"), dialogTitle: clipTitle(clip) });
};

/** Local copies of images this phone sent, by clip id, for previews. Kept for this run of the app. */
const localImages = new Map<string, string>();

/** A preview for an image clip: the Mac's thumbnail, else the file this phone sent. */
export const imageUri = (clip: Clip): string | null => (clip.thumb === null ? (localImages.get(clip.id) ?? null) : `data:image/jpeg;base64,${clip.thumb}`);

/** One thing picked, pasted or shared in, before it is sent. */
export type Picked = PickedText | PickedFile;
export interface PickedText {
  readonly kind: "text" | "link";
  readonly text: string;
}
export interface PickedFile {
  readonly kind: "image" | "file";
  readonly uri: string;
  readonly name: string;
  readonly mime: string | null;
  readonly size: number;
}

export const isFile = (item: Picked): item is PickedFile => "uri" in item;

/** What the send sheet shows and sends: one or more picked things. */
export interface Batch {
  readonly items: ReadonlyArray<Picked>;
  readonly label: string;
  readonly bytes: number;
  /** Where it goes unless changed: the clipboard for text, links and images, Downloads for files. */
  readonly to: ClipDestination;
  /** Where it came from, e.g. "from Files" or "shared from Gallery". */
  readonly from: string;
}

const plural = (count: number, one: string, many: string): string => `${String(count)} ${count === 1 ? one : many}`;

export const batchOf = (items: ReadonlyArray<Picked>, from: string): Batch => {
  const files = items.filter(isFile);
  const images = items.filter((item) => item.kind === "image").length;
  const first = items[0];
  const label =
    items.length === 1 && first !== undefined
      ? isFile(first)
        ? first.name
        : first.kind === "link"
          ? "A link"
          : "Text"
      : images === items.length
        ? plural(images, "photo", "photos")
        : plural(items.length, "item", "items");
  return {
    items,
    label,
    bytes: files.reduce((sum, item) => sum + item.size, 0),
    to: items.some((item) => item.kind === "file") ? "downloads" : "clipboard",
    from,
  };
};

/** Text turns into a link when it is one URL and nothing else. */
export const textItem = (text: string): Picked => ({ kind: isLink(text) ? "link" : "text", text: text.trim() });

const sha256Of = async (uri: string, size: number): Promise<string | null> => (size > HASH_UP_TO ? null : new File(uri).digest("SHA-256").catch(() => null));

/** Opens each picked file and hashes it, ready for the transfer engine. */
const outgoingOf = async (item: Picked): Promise<Outgoing> => {
  if (!isFile(item)) return item;
  const kind: SendKind = item.kind;
  return { kind, name: item.name, mime: item.mime, sha256: await sha256Of(item.uri, item.size), source: fileSource(item.uri) };
};

/** "2 photos are on your Mac's clipboard", or just "On your Mac's clipboard" for text. */
const placedLine = (batch: Batch, to: ClipDestination): string => {
  const where = to === "clipboard" ? "on your Mac's clipboard" : "in Downloads on your Mac";
  const only = batch.items.length === 1 ? batch.items[0] : undefined;
  if (only !== undefined && !isFile(only)) return where.charAt(0).toUpperCase() + where.slice(1);
  return `${batch.label} ${batch.items.length > 1 ? "are" : "is"} ${where}`;
};

/** Macs from before clip history take plain text only, through the old ClipboardSet command. */
const sendToOldMac = async (remote: Remote, batch: Batch): Promise<boolean> => {
  const texts = batch.items.filter((item) => !isFile(item));
  if (texts.length < batch.items.length) {
    toast.show("Update Vitals on your Mac to send photos and files", { tone: "bad" });
    return false;
  }
  return send(remote, { _tag: "ClipboardSet", text: texts.map((item) => item.text).join("\n") }, "On your Mac's clipboard");
};

/** Sends a batch to the Mac and says where it landed. Progress shows in the transfer strip. */
export const sendBatch = async (remote: Remote, batch: Batch, to: ClipDestination): Promise<boolean> => {
  if (remote.clips.supported.get() === false) return sendToOldMac(remote, batch);
  let items: ReadonlyArray<Outgoing>;
  try {
    items = await Promise.all(batch.items.map(outgoingOf));
  } catch {
    toast.show("Vitals could not open that file", { tone: "bad" });
    return false;
  }
  const clips = await remote.clips.send(`Sending ${batch.label}`, items, to).result;
  if (clips === null) return false;
  // The Mac makes no thumbnails for phone-sent images, so rows show the local file while it's around.
  clips.forEach((clip, index) => {
    const item = batch.items[index];
    if (clip.kind === "image" && item !== undefined && isFile(item)) localImages.set(clip.id, item.uri);
  });
  toast.show(placedLine(batch, to));
  return true;
};

/** Writes a pasted image (base64) to the cache, so it sends like any other file. */
export const pastedImage = (dataUri: string): Picked => {
  const base64 = dataUri.replace(/^data:[^,]*,/, "");
  const mime = /^data:([^;,]+)/.exec(dataUri)?.[1] ?? "image/png";
  const name = `Pasted image ${new Date().toISOString().slice(0, 19).replace(/[T:]/g, "-")}.${mime === "image/jpeg" ? "jpg" : "png"}`;
  const folder = new Directory(Paths.cache, "pasted");
  folder.create({ intermediates: true, idempotent: true });
  const file = new File(folder, name);
  file.create({ overwrite: true });
  file.writeSync(base64, { encoding: "base64" });
  return { kind: "image", uri: file.uri, name, mime, size: file.size };
};

/**
 * A picked or shared file's own name. Android pickers often hand over only `content://…/67`,
 * so when the URI ends in an id, the name is "Photo.jpeg" / "File.pdf" from the mime type.
 */
export const nameFromUri = (uri: string, kind: PickedFile["kind"], mime: string | null): string => {
  const last = decodeURIComponent(uri.split("/").pop() ?? "");
  if (/\.[A-Za-z0-9]{1,8}$/.test(last)) return last;
  const ext = (mime?.split("/")[1] ?? "").replace(/[^a-z0-9]/gi, "").slice(0, 8);
  const base = kind === "image" ? "Photo" : "File";
  return ext === "" ? base : `${base}.${ext}`;
};

/** The system photo picker. No permission prompt: the picker runs outside the app on both platforms. */
export const pickPhotos = async (): Promise<Batch | null> => {
  const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images", "videos"], allowsMultipleSelection: true, selectionLimit: 20, quality: 1 });
  if (result.canceled || result.assets.length === 0) return null;
  const items = result.assets.map(
    (asset): PickedFile => ({
      kind: asset.type === "video" ? "file" : "image",
      uri: asset.uri,
      name: asset.fileName ?? nameFromUri(asset.uri, asset.type === "video" ? "file" : "image", asset.mimeType ?? null),
      mime: asset.mimeType ?? null,
      size: asset.fileSize ?? 0,
    }),
  );
  return batchOf(items, "from Photos");
};

/** The system file picker. Files go to Downloads unless changed. */
export const pickFiles = async (): Promise<Batch | null> => {
  const result = await DocumentPicker.getDocumentAsync({ multiple: true, copyToCacheDirectory: true });
  if (result.canceled || result.assets.length === 0) return null;
  const items = result.assets.map((asset): PickedFile => ({ kind: "file", uri: asset.uri, name: asset.name, mime: asset.mimeType ?? null, size: asset.size ?? 0 }));
  return batchOf(items, "from Files");
};
