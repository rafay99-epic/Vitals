import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge } from "@vitals/app/features/clips/format.ts";
import { thumbKey } from "@vitals/app/state/files.ts";
import { useSelect } from "@vitals/app/state/useStore.ts";
import type { DeviceId, FsEntry, FsRecentKind } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { useCallback } from "react";
import { Image, StyleSheet, View } from "react-native";

import { color, Icon, type IconName, T, Tap } from "./ui/index.ts";

export const KIND_TITLE: Readonly<Record<FsRecentKind, string>> = { photos: "Photos", screenshots: "Screenshots", downloads: "Downloads", documents: "Documents" };

/** Photos and screenshots show as pictures; downloads and documents as rows. */
export const isGallery = (kind: FsRecentKind): boolean => kind === "photos" || kind === "screenshots";

const EXTENSIONS: ReadonlyArray<readonly [RegExp, IconName, string]> = [
  [/\.(jpe?g|png|gif|heic|heif|webp|tiff?|bmp|svg|psd)$/i, "image", color.pink],
  [/\.(mov|mp4|m4v|avi|mkv|webm)$/i, "video", color.blue],
  [/\.apk$/i, "android", color.green],
  [/\.(zip|xip|dmg|tar|gz|7z|rar|pkg)$/i, "files", color.orange],
];

const lookOf = (entry: FsEntry): { readonly icon: IconName; readonly tint: string } => {
  if (entry.kind === "folder") return { icon: "folder", tint: color.blue };
  if (entry.kind === "package") return { icon: "files", tint: color.violet };
  if (entry.kind === "link") return { icon: "link", tint: color.dim };
  const match = EXTENSIONS.find(([pattern]) => pattern.test(entry.name));
  return match === undefined ? { icon: "file", tint: color.ink2 } : { icon: match[1], tint: match[2] };
};

const metaOf = (entry: FsEntry, now: number): string =>
  entry.kind === "folder" ? clipAge(entry.modifiedAt, now) : [entry.kind === "package" ? "package" : formatBytes(entry.size), clipAge(entry.modifiedAt, now)].join(" · ");

/** The thumbnail for an entry on the Mac or on `device`, once fetched. */
export const useThumb = (path: string, device?: DeviceId): string | null => {
  const thumbs = useRemote().files.thumbs;
  const key = thumbKey(path, device);
  const select = useCallback((map: ReadonlyMap<string, string | null>) => map.get(key) ?? null, [key]);
  return useSelect(thumbs, select);
};

/** The entry's thumbnail, or its kind icon until there is one. */
function FsThumb({ entry, device, square = false, dim = false }: { readonly entry: FsEntry; readonly device?: DeviceId | undefined; readonly square?: boolean; readonly dim?: boolean }) {
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

/** One file or folder: thumbnail, name, size and age. Shows a check while selecting. */
export function EntryRow({
  entry,
  device,
  now,
  selecting = false,
  selected = false,
  onPress,
  onLongPress,
}: {
  readonly entry: FsEntry;
  readonly device?: DeviceId | undefined;
  readonly now: number;
  readonly selecting?: boolean;
  readonly selected?: boolean;
  readonly onPress: (entry: FsEntry) => void;
  readonly onLongPress?: ((entry: FsEntry) => void) | undefined;
}) {
  const meta = metaOf(entry, now);
  return (
    <Tap
      onPress={() => onPress(entry)}
      onLongPress={onLongPress === undefined ? undefined : () => onLongPress(entry)}
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
      {selecting && entry.kind !== "folder" ? <Check on={selected} /> : entry.kind === "folder" ? <Icon name="chevron" size={15} color={color.mute} /> : null}
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
  onLongPress,
}: {
  readonly entry: FsEntry;
  readonly device?: DeviceId | undefined;
  readonly size: number;
  readonly selecting?: boolean;
  readonly selected?: boolean;
  readonly onPress: (entry: FsEntry) => void;
  readonly onLongPress?: ((entry: FsEntry) => void) | undefined;
}) {
  return (
    <Tap
      onPress={() => onPress(entry)}
      onLongPress={onLongPress === undefined ? undefined : () => onLongPress(entry)}
      accessibilityRole="button"
      accessibilityLabel={entry.name}
      accessibilityState={{ selected }}
      scale={0.97}
      style={{ width: size, height: size }}
    >
      <FsThumb entry={entry} device={device} square dim={selected} />
      {selecting ? (
        <View style={styles.squareCheck}>
          <Check on={selected} />
        </View>
      ) : null}
    </Tap>
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
});
