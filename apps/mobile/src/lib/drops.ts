import type { Remote } from "@vitals/app/state/remote.ts";
import type { DropLive, OutgoingFile, SavedFile } from "@vitals/app/state/drops.ts";
import { formatAmount } from "@vitals/app/features/clips/format.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { canInstallApps, dropSupported, installApk, openFile } from "@vitals/tailnet/drop";
import { Directory, File } from "expo-file-system";
import * as MediaLibrary from "expo-media-library";
import * as Sharing from "expo-sharing";
import { Platform } from "react-native";

import { toast } from "../ui/Toast.tsx";
import { type Batch, batchOf, isFile, type PickedFile } from "./clips.ts";

export { canInstallApps };

export const savedTo = Platform.OS === "ios" ? "Files › On My iPhone › Vitals" : "Downloads › Vitals";

export const macFolder = "Downloads › Vitals";

export const keepsGoing = Platform.OS === "ios" ? "Keeps going if you leave Vitals. On iPhone, for about 30 seconds." : "Keeps going if you leave Vitals.";

export type FileKind = "apk" | "video" | "image" | "doc";

const VIDEO = /\.(mov|mp4|m4v|mkv|webm|avi|3gp)$/i;
const IMAGE = /\.(jpe?g|png|gif|heic|heif|webp|bmp|tiff?|dng)$/i;

export const fileKind = (name: string, mime: string | null): FileKind => {
  if (/\.apk$/i.test(name) || mime === "application/vnd.android.package-archive") return "apk";
  if (mime?.startsWith("video/") === true || VIDEO.test(name)) return "video";
  if (mime?.startsWith("image/") === true || IMAGE.test(name)) return "image";
  return "doc";
};

export const KIND_NAME: Readonly<Record<FileKind, string>> = { apk: "App", video: "Video", image: "Photo", doc: "Document" };

const sizeOf = (uri: string): number => {
  try {
    return new File(uri).size;
  } catch {
    return 0;
  }
};

const outgoingOf = (item: PickedFile): OutgoingFile => ({ uri: item.uri, name: item.name, path: item.path ?? null, size: item.size > 0 ? item.size : sizeOf(item.uri), mime: item.mime });

export type FilesBlock = "oldApp" | "oldMac" | "off" | null;

export const useFilesBlock = (): FilesBlock => {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const supported = useStore(remote.drops.supported);
  if (!dropSupported) return "oldApp";
  if (state._tag === "Ready" && state.hello.drop !== true) return "oldMac";
  if (supported === false) return "off";
  return null;
};

export const BLOCK_NOTE: Readonly<Record<Exclude<FilesBlock, null>, string>> = {
  oldApp: "File transfer needs the latest app.",
  oldMac: "Update Vitals on your Mac to send files.",
  off: "Files are off for this phone. Turn them on in Vitals on the Mac.",
};

export const sendDrop = async (remote: Remote, batch: Batch, dest?: string): Promise<boolean> => {
  const files = batch.items.filter(isFile).map(outgoingOf);
  return (await remote.drops.send(files, dest === undefined ? {} : { dest })) !== null;
};

const walk = (folder: Directory, prefix: string): ReadonlyArray<PickedFile> =>
  folder.list().flatMap((entry): ReadonlyArray<PickedFile> => {
    const path = `${prefix}/${entry.name}`;
    if (entry instanceof Directory) return walk(entry, path);
    return [{ kind: fileKind(entry.name, entry.type || null) === "image" ? "image" : "file", uri: entry.uri, name: entry.name, mime: entry.type || null, size: entry.size, path }];
  });

export const pickFolder = async (): Promise<Batch | null> => {
  const folder = await Directory.pickDirectoryAsync().catch(() => null);
  if (folder === null) return null;
  const items = walk(folder, folder.name);
  if (items.length === 0) {
    toast.show("That folder is empty");
    return null;
  }
  const batch = batchOf(items, `${String(items.length)} ${items.length === 1 ? "file" : "files"}, keeps its folders`);
  return { ...batch, label: folder.name, to: "downloads" };
};

export const liveLine = (live: DropLive | null, waiting: string | null): string => {
  if (waiting !== null) return waiting;
  if (live === null) return "Starting";
  if (live.failed) return "Stopped";
  if (live.stalled) return "Waiting for your Mac";
  const amount = formatAmount(live.done, live.total);
  return live.route === null ? amount : `${amount} · ${live.route === "lan" ? "Wi-Fi" : "Tailscale"}`;
};

export const percent = (live: DropLive | null): string => `${String(live === null || live.total === 0 ? 0 : Math.round((live.done / live.total) * 100))}%`;

export const openSaved = async (file: SavedFile): Promise<void> => {
  if (file.uri === null) return toast.show("Vitals can't find that file anymore", { tone: "bad" });
  await openFile(file.uri, file.mime).catch(() => toast.show("No app on this phone opens that file", { tone: "bad" }));
};

export const installSaved = async (file: SavedFile): Promise<void> => {
  if (file.uri === null) return toast.show("Vitals can't find that file anymore", { tone: "bad" });
  await installApk(file.uri).catch(() => toast.show("Android's installer didn't open. Allow Vitals to install apps in Settings.", { tone: "bad" }));
};

export const shareSaved = async (file: SavedFile): Promise<void> => {
  if (file.uri === null) return toast.show("Vitals can't find that file anymore", { tone: "bad" });
  await Sharing.shareAsync(file.uri, { mimeType: file.mime ?? "application/octet-stream", dialogTitle: file.name }).catch(() => toast.show("Sharing didn't open", { tone: "bad" }));
};

export const saveSavedToPhotos = async (file: SavedFile): Promise<void> => {
  if (file.uri === null) return toast.show("Vitals can't find that file anymore", { tone: "bad" });
  const permission = await MediaLibrary.requestPermissionsAsync(true, ["photo", "video"]);
  if (!permission.granted) return toast.show("Vitals can't save to Photos. Allow it in Settings.", { tone: "bad" });
  const saved = await MediaLibrary.Asset.create(file.uri).then(
    () => true,
    () => false,
  );
  toast.show(saved ? "Saved to Photos" : "Photos didn't take that file", saved ? {} : { tone: "bad" });
};
