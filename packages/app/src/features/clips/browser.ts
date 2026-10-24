import type { Clip, ClipDestination } from "@vitals/contracts";

import { fromBase64, toBase64 } from "../../lib/base64.ts";
import type { Remote } from "../../state/remote.ts";
import type { ByteSink, ByteSource, Outgoing } from "../../state/transfer.ts";
import { clipTitle, fileNameOf, isLink } from "./format.ts";

/** Browser-only clipboard IO for the web client. Everything here checks for a DOM first. */
export const hasDom = typeof document !== "undefined";

/** Reads a File or Blob a slice at a time. */
const blobSource = (blob: Blob): ByteSource => ({
  size: blob.size,
  read: async (offset, length) => toBase64(new Uint8Array(await blob.slice(offset, offset + length).arrayBuffer())),
});

/** Collects chunks and turns them into one Blob at the end. */
const blobSink = (mime: string): { readonly sink: ByteSink; readonly blob: () => Blob } => {
  const parts = new Map<number, Uint8Array<ArrayBuffer>>();
  return {
    sink: {
      write: async (offset, base64) => {
        parts.set(offset, fromBase64(base64));
      },
      finish: async () => {},
      abort: () => parts.clear(),
    },
    blob: () => new Blob([...parts.entries()].sort(([left], [right]) => left - right).map(([, part]) => part), { type: mime }),
  };
};

const saveBlob = (blob: Blob, name: string): void => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
};

const fetchBlob = async (remote: Remote, clip: Clip): Promise<Blob | null> => {
  const mime = clip.kind === "folder" ? "application/zip" : (clip.mime ?? "application/octet-stream");
  const { sink, blob } = blobSink(mime);
  const done = await remote.clips.fetch(`Getting ${clipTitle(clip)}`, clip, sink).result;
  return done === null ? null : blob();
};

/** Copies a text or link clip, reading the rest from the Mac when only a preview came inline. */
export const copyClipText = async (remote: Remote, clip: Clip): Promise<boolean> => {
  const text = clip.truncated ? await fetchBlob(remote, clip).then((blob) => blob?.text() ?? null) : clip.text;
  if (text === null) return false;
  await navigator.clipboard.writeText(text);
  return true;
};

/** Downloads a clip into the browser's Downloads. Folders arrive as a zip. */
export const downloadClip = async (remote: Remote, clip: Clip): Promise<boolean> => {
  const blob = await fetchBlob(remote, clip);
  if (blob === null) return false;
  saveBlob(blob, fileNameOf(clip));
  return true;
};

/** Files go to Downloads; images and text to the Mac clipboard. */
const destinationOf = (items: ReadonlyArray<Outgoing>): ClipDestination => (items.some((item) => item.kind === "file") ? "downloads" : "clipboard");

const fileItem = (file: File): Outgoing => ({
  kind: file.type.startsWith("image/") ? "image" : "file",
  name: file.name || "Untitled",
  mime: file.type === "" ? null : file.type,
  sha256: null,
  source: blobSource(file),
});

/** Sends dropped, picked or pasted files (or text) to the Mac and confirms where they landed. */
export const sendToMac = async (remote: Remote, files: ReadonlyArray<File>, text: string | null): Promise<boolean> => {
  const items: ReadonlyArray<Outgoing> = text !== null ? [{ kind: isLink(text) ? "link" : "text", text: text.trim() }] : files.map(fileItem);
  if (items.length === 0) return false;
  const label = text !== null ? "text" : files.length === 1 ? (files[0]?.name ?? "a file") : `${String(files.length)} files`;
  const to = destinationOf(items);
  const clips = await remote.clips.send(`Sending ${label}`, items, to).result;
  if (clips === null) return false;
  remote.show(to === "clipboard" ? "On the Mac clipboard." : "In Downloads on the Mac.");
  return true;
};

/** Opens the browser's file picker. */
export const chooseFiles = (onFiles: (files: ReadonlyArray<File>) => void): void => {
  const input = document.createElement("input");
  input.type = "file";
  input.multiple = true;
  input.addEventListener("change", () => onFiles(Array.from(input.files ?? [])));
  input.click();
};

/** Lets a DOM node take dropped files. Returns a cleanup. React Native Web renders a View as a plain element. */
export const acceptDrops = (node: unknown, onFiles: (files: ReadonlyArray<File>) => void): (() => void) => {
  if (!hasDom || !(node instanceof HTMLElement)) return () => {};
  const over = (event: DragEvent) => event.preventDefault();
  const drop = (event: DragEvent) => {
    event.preventDefault();
    const files = Array.from(event.dataTransfer?.files ?? []);
    if (files.length > 0) onFiles(files);
  };
  node.addEventListener("dragover", over);
  node.addEventListener("drop", drop);
  return () => {
    node.removeEventListener("dragover", over);
    node.removeEventListener("drop", drop);
  };
};

/** Paste anywhere outside a text field sends what was pasted. Returns a cleanup. */
export const sendOnPaste = (onPaste: (files: ReadonlyArray<File>, text: string | null) => void): (() => void) => {
  if (!hasDom) return () => {};
  const paste = (event: ClipboardEvent) => {
    const target = event.target;
    if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) return;
    const files = Array.from(event.clipboardData?.files ?? []);
    const text = event.clipboardData?.getData("text/plain") ?? "";
    if (files.length === 0 && text.trim() === "") return;
    event.preventDefault();
    onPaste(files, files.length > 0 ? null : text);
  };
  document.addEventListener("paste", paste);
  return () => document.removeEventListener("paste", paste);
};
