import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge } from "@vitals/app/features/clips/format.ts";
import { type FsSource, thumbKey } from "@vitals/app/state/files.ts";
import { useSelect } from "@vitals/app/state/useStore.ts";
import type { DeviceId, FsEntry, FsRecentKind, FsRoot } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { useCallback, useState } from "react";
import { Image, StyleSheet, View } from "react-native";

import { fileKind } from "./lib/drops.ts";
import { color, Icon, type IconName, T, Tap } from "./ui/index.ts";

export type ShownKind = FsRecentKind | "images";

export const KIND_TITLE: Readonly<Record<ShownKind, string>> = { photos: "Photos", screenshots: "Screenshots", downloads: "Downloads", documents: "Documents", images: "Images" };

/** Photos and screenshots show as pictures; downloads and documents as rows. */
export const isGallery = (kind: ShownKind): boolean => kind !== "downloads" && kind !== "documents";

/** Pictures go in a grid inside folders; everything else is a row. */
export const isPicture = (entry: FsEntry): boolean => entry.kind === "file" && fileKind(entry.name, null) === "image";

export const isFolder = (entry: FsEntry): boolean => entry.kind === "folder" || entry.kind === "link";

/** "your Mac", or the phone's name. */
export const whereOf = (source: FsSource): string => (source.device === null ? "your Mac" : source.name);

/** "Report.pdf", or "3 files". */
export const whatOf = (entries: ReadonlyArray<FsEntry>): string => (entries.length === 1 ? (entries[0]?.name ?? "1 file") : `${String(entries.length)} files`);

const EXTENSIONS: ReadonlyArray<readonly [RegExp, IconName, string]> = [
  [/\.(jpe?g|png|gif|heic|heif|webp|tiff?|bmp|svg|psd)$/i, "image", color.pink],
  [/\.(mov|mp4|m4v|avi|mkv|webm)$/i, "video", color.blue],
  [/\.apk$/i, "android", color.green],
  [/\.(zip|xip|dmg|tar|gz|7z|rar|pkg)$/i, "files", color.orange],
];

const lookOf = (entry: FsEntry): { readonly icon: IconName; readonly tint: string } => {
  if (entry.kind === "folder") return { icon: "folder", tint: color.green };
  if (entry.kind === "package") return { icon: "files", tint: color.violet };
  if (entry.kind === "link") return { icon: "link", tint: color.dim };
  const match = EXTENSIONS.find(([pattern]) => pattern.test(entry.name));
  return match === undefined ? { icon: "file", tint: color.orange } : { icon: match[1], tint: match[2] };
};

const metaOf = (entry: FsEntry, now: number): string =>
  entry.kind === "folder" ? clipAge(entry.modifiedAt, now) : [entry.kind === "package" ? "package" : formatBytes(entry.size), clipAge(entry.modifiedAt, now)].join(" · ");

/** The thumbnail for an entry on the Mac or on `device`, once fetched. */
export const useThumb = (path: string, device: DeviceId | null): string | null => {
  const thumbs = useRemote().files.thumbs;
  const key = thumbKey(path, device ?? undefined);
  const select = useCallback((map: ReadonlyMap<string, string | null>) => map.get(key) ?? null, [key]);
  return useSelect(thumbs, select);
};

/** The entry's thumbnail, or its kind icon until there is one. */
function FsThumb({ entry, device, square = false, dim = false }: { readonly entry: FsEntry; readonly device: DeviceId | null; readonly square?: boolean; readonly dim?: boolean }) {
  const uri = useThumb(entry.path, device);
  const shape = [square ? styles.square : styles.icon, dim ? styles.dim : null];
  if (uri !== null) return <Image source={{ uri }} style={shape} accessibilityIgnoresInvertColors />;
  const look = lookOf(entry);
  return (
    <View style={[shape, styles.iconTile]}>
      <Icon name={look.icon} size={16} color={look.tint} />
    </View>
  );
}

function Check({ on }: { readonly on: boolean }) {
  return <View style={[styles.check, on ? styles.checkOn : null]}>{on ? <Icon name="check" size={13} color={color.bg} weight={2.6} /> : null}</View>;
}

/** One file or folder: thumbnail, name, size and age. Files show a check while selecting. */
export function EntryRow({
  entry,
  device,
  now,
  selecting = false,
  selected = false,
  onPress,
}: {
  readonly entry: FsEntry;
  readonly device: DeviceId | null;
  readonly now: number;
  readonly selecting?: boolean;
  readonly selected?: boolean;
  readonly onPress: (entry: FsEntry) => void;
}) {
  const meta = metaOf(entry, now);
  const folder = isFolder(entry);
  return (
    <Tap
      onPress={() => onPress(entry)}
      accessibilityRole="button"
      accessibilityLabel={`${entry.name}, ${meta}`}
      accessibilityState={{ selected }}
      scale={0.99}
      style={[styles.row, selected ? styles.picked : null]}
    >
      <FsThumb entry={entry} device={device} />
      <View style={styles.rowText}>
        <T v="medium" numberOfLines={1}>
          {entry.name}
        </T>
        <T v="small" numberOfLines={1}>
          {meta}
        </T>
      </View>
      {folder ? <Icon name="chevron" size={15} color={color.mute} /> : selecting ? <Check on={selected} /> : null}
    </Tap>
  );
}

/** A square photo or screenshot, for strips and grids. */
export function PhotoTile({
  entry,
  device,
  size,
  selecting = false,
  selected = false,
  onPress,
}: {
  readonly entry: FsEntry;
  readonly device: DeviceId | null;
  readonly size: number;
  readonly selecting?: boolean;
  readonly selected?: boolean;
  readonly onPress: (entry: FsEntry) => void;
}) {
  return (
    <Tap onPress={() => onPress(entry)} accessibilityRole="button" accessibilityLabel={entry.name} accessibilityState={{ selected }} scale={0.97} style={{ width: size, height: size }}>
      <FsThumb entry={entry} device={device} square dim={selected} />
      {selecting ? (
        <View style={styles.squareCheck}>
          <Check on={selected} />
        </View>
      ) : null}
    </Tap>
  );
}

const PLACE_ICON: Readonly<Record<FsRoot["place"], IconName>> = {
  home: "home",
  desktop: "screen",
  documents: "file",
  downloads: "down",
  movies: "video",
  music: "sound",
  pictures: "image",
  disk: "mac",
  volume: "files",
  photos: "image",
  storage: "android",
  folder: "folder",
};

/** One of a device's shared folders. */
export function RootRow({ root, onPress }: { readonly root: FsRoot; readonly onPress: (root: FsRoot) => void }) {
  return (
    <Tap onPress={() => onPress(root)} accessibilityRole="button" accessibilityLabel={root.label} scale={0.99} style={styles.row}>
      <View style={[styles.icon, styles.iconTile]}>
        <Icon name={PLACE_ICON[root.place]} size={16} color={color.green} />
      </View>
      <T v="medium" numberOfLines={1} style={styles.rowText}>
        {root.label}
      </T>
      <Icon name="chevron" size={15} color={color.mute} />
    </Tap>
  );
}

/** A kind on the device page: its name, how old the newest one is, and that one peeking out. */
export function KindTile({ kind, newest, line, device, now, onPress }: { readonly kind: FsRecentKind; readonly newest: FsEntry | null; readonly line: string | null; readonly device: DeviceId | null; readonly now: number; readonly onPress: () => void }) {
  const text = line ?? (newest === null ? "Nothing yet" : `Newest: ${clipAge(newest.modifiedAt, now)}`);
  return (
    <Tap onPress={onPress} accessibilityRole="button" accessibilityLabel={`${KIND_TITLE[kind]}, ${text}`} layout={styles.kindSlot} style={styles.kind}>
      <T v="strong">{KIND_TITLE[kind]}</T>
      <T v="small" numberOfLines={1}>
        {text}
      </T>
      {newest === null ? null : (
        <View style={styles.peek}>
          <FsThumb entry={newest} device={device} square />
        </View>
      )}
    </Tap>
  );
}

/** Picking several files on a screen. `toggle` adds or drops one; `stop` clears and leaves picking. */
export const useSelection = () => {
  const [selecting, setSelecting] = useState(false);
  const [picked, setPicked] = useState<ReadonlyMap<string, FsEntry>>(new Map());
  const toggle = (entry: FsEntry) =>
    setPicked((current) => {
      const next = new Map(current);
      if (next.has(entry.path)) next.delete(entry.path);
      else next.set(entry.path, entry);
      return next;
    });
  const stop = () => {
    setSelecting(false);
    setPicked(new Map());
  };
  return { selecting, picked, toggle, stop, start: () => setSelecting(true) };
};

/** "Select" at the top right, "Done" while selecting. */
export function SelectButton({ selecting, onPress }: { readonly selecting: boolean; readonly onPress: () => void }) {
  return (
    <Tap onPress={onPress} accessibilityRole="button" hitSlop={12} style={styles.select}>
      <T v="strong" color={color.yellow}>
        {selecting ? "Done" : "Select"}
      </T>
    </Tap>
  );
}

/** The bar above the dock while selecting: how many, and Transfer. */
export function SelectBar({ count, bottom, onTransfer }: { readonly count: number; readonly bottom: number; readonly onTransfer: () => void }) {
  return (
    <View style={[styles.bar, { bottom }]}>
      <T v="strong" color={color.bg} style={styles.rowText}>
        {count === 0 ? "Tap to select" : `${String(count)} selected`}
      </T>
      <Tap onPress={onTransfer} disabled={count === 0} accessibilityRole="button" style={styles.barButton}>
        <T v="strong" color={color.yellow}>
          Transfer
        </T>
      </Tap>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 8, minHeight: 52 },
  picked: { backgroundColor: "rgba(242,236,107,0.06)" },
  rowText: { flex: 1 },
  icon: { width: 34, height: 34, borderRadius: 10 },
  iconTile: { backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  square: { width: "100%", height: "100%", borderRadius: 10 },
  dim: { opacity: 0.6 },
  squareCheck: { position: "absolute", top: 6, right: 6 },
  check: { width: 22, height: 22, borderRadius: 11, borderWidth: 1.5, borderColor: color.line2, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(0,0,0,0.35)" },
  checkOn: { backgroundColor: color.yellow, borderColor: color.yellow },
  kindSlot: { width: "47%", flexGrow: 1 },
  kind: { height: 92, borderRadius: 18, backgroundColor: color.s2, padding: 13, gap: 3, overflow: "hidden" },
  peek: { position: "absolute", right: -6, bottom: -12, width: 50, height: 66, borderRadius: 9, overflow: "hidden", transform: [{ rotate: "-8deg" }] },
  select: { paddingHorizontal: 20, paddingVertical: 8 },
  bar: { position: "absolute", left: 14, right: 14, flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: color.ink, borderRadius: 18, paddingVertical: 10, paddingLeft: 16, paddingRight: 10 },
  barButton: { backgroundColor: color.bg, borderRadius: 12, paddingVertical: 9, paddingHorizontal: 14 },
});
