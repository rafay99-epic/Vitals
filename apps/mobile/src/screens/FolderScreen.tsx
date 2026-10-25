import { LegendList } from "@legendapp/list/react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge } from "@vitals/app/features/clips/format.ts";
import { FILES_PAGE, hasPreview } from "@vitals/app/state/files.ts";
import { useSelect } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { FsEntry, FsSort } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { useCallback, useEffect, useState } from "react";
import { Image, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { pickFiles } from "../lib/clips.ts";
import { sendDrop } from "../lib/drops.ts";
import { useAccess } from "../lib/remote.ts";
import type { ControlStackParams } from "../navigation.ts";
import { macFileSheet } from "../sheets/MacFileSheet.tsx";
import { BackBar, color, Empty, Icon, type IconName, Segmented, sheet, T, Tap, Title, toast, useDockSpace } from "../ui/index.ts";

type Props = NativeStackScreenProps<ControlStackParams, "Folder">;

type Listing =
  | { readonly _tag: "loading" }
  | { readonly _tag: "failed"; readonly message: string }
  | { readonly _tag: "loaded"; readonly entries: ReadonlyArray<FsEntry>; readonly total: number; readonly more: boolean };

const SORTS: ReadonlyArray<{ readonly value: FsSort; readonly label: string }> = [
  { value: "name", label: "Name" },
  { value: "date", label: "Newest" },
  { value: "size", label: "Biggest" },
];

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

function Thumb({ entry }: { readonly entry: FsEntry }) {
  const thumbs = useRemote().files.thumbs;
  const select = useCallback((map: ReadonlyMap<string, string | null>) => map.get(entry.path) ?? null, [entry.path]);
  const uri = useSelect(thumbs, select);
  if (uri !== null) return <Image source={{ uri }} style={styles.icon} accessibilityIgnoresInvertColors />;
  const look = lookOf(entry);
  return (
    <View style={[styles.icon, styles.iconTile]}>
      <Icon name={look.icon} size={16} color={look.tint} />
    </View>
  );
}

function EntryRow({ entry, now, selecting, selected, onPress }: { readonly entry: FsEntry; readonly now: number; readonly selecting: boolean; readonly selected: boolean; readonly onPress: (entry: FsEntry) => void }) {
  const meta = metaOf(entry, now);
  return (
    <Tap onPress={() => onPress(entry)} accessibilityRole="button" accessibilityLabel={`${entry.name}, ${meta}`} accessibilityState={{ selected }} scale={0.99} style={[styles.row, selected ? styles.picked : null]}>
      <Thumb entry={entry} />
      <View style={styles.rowText}>
        <T v="medium" numberOfLines={1}>
          {entry.name}
        </T>
        <T v="small" numberOfLines={1}>
          {meta}
        </T>
      </View>
      {selecting && entry.kind !== "folder" ? (
        <View style={[styles.check, selected ? styles.checkOn : null]}>{selected ? <Icon name="check" size={13} color={color.bg} weight={2.6} /> : null}</View>
      ) : entry.kind === "folder" ? (
        <Icon name="chevron" size={15} color={color.mute} />
      ) : null}
    </Tap>
  );
}

export function FolderScreen({ navigation, route }: Props) {
  const remote = useRemote();
  const access = useAccess();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(60_000);
  const { path, title, device, deviceName } = route.params;
  const [sort, setSort] = useState<FsSort>("name");
  const [listing, setListing] = useState<Listing>({ _tag: "loading" });
  const [selecting, setSelecting] = useState(false);
  const [picked, setPicked] = useState<ReadonlyMap<string, FsEntry>>(new Map());

  useEffect(() => {
    let cancelled = false;
    void remote.files.list(path, sort, 0, device).then((outcome) => {
      if (cancelled) return;
      setListing(outcome.ok ? { _tag: "loaded", entries: outcome.value.entries, total: outcome.value.total, more: false } : { _tag: "failed", message: outcome.message });
      if (outcome.ok) remote.files.want(outcome.value.entries.slice(0, 40), device);
    });
    return () => {
      cancelled = true;
    };
  }, [remote, path, sort, device]);

  const loadMore = () => {
    if (listing._tag !== "loaded" || listing.more || listing.entries.length >= listing.total) return;
    const shown = listing.entries;
    setListing({ ...listing, more: true });
    void remote.files.list(path, sort, shown.length, device).then((outcome) => {
      setListing((current) => (current._tag !== "loaded" ? current : outcome.ok ? { _tag: "loaded", entries: [...shown, ...outcome.value.entries], total: outcome.value.total, more: false } : { ...current, more: false }));
    });
  };

  const open = (entry: FsEntry) => {
    if (entry.kind === "folder" || entry.kind === "link") {
      navigation.push("Folder", { path: entry.path, title: entry.name, ...(device === undefined ? {} : { device, deviceName: deviceName ?? "" }) });
      return;
    }
    if (!selecting) {
      sheet.open(macFileSheet(entry, device === undefined && access.change, device === undefined ? null : { device, name: deviceName ?? "That phone" }));
      return;
    }
    setPicked((current) => {
      const next = new Map(current);
      if (next.has(entry.path)) next.delete(entry.path);
      else next.set(entry.path, entry);
      return next;
    });
  };

  const get = async () => {
    const entries = [...picked.values()];
    setSelecting(false);
    setPicked(new Map());
    const what = entries.length === 1 ? (entries[0]?.name ?? "it") : `${String(entries.length)} files`;
    if (device !== undefined) {
      const outcome = await remote.files.pull(device, entries.map((entry) => entry.path));
      toast.show(outcome.ok ? `${deviceName ?? "That phone"} is sending ${what} through your Mac` : outcome.message, { tone: outcome.ok ? "ok" : "bad" });
      return;
    }
    const drop = await remote.drops.pull(entries.map((entry) => entry.path));
    if (drop !== null) toast.show(`Getting ${what} from your Mac`);
  };

  const putHere = async () => {
    const batch = await pickFiles();
    if (batch === null) return;
    if (await sendDrop(remote, batch, path)) toast.show(`Sending ${batch.label} to ${title} on your Mac`);
  };

  const onViewable = useCallback(
    ({ viewableItems }: { readonly viewableItems: ReadonlyArray<{ readonly item: FsEntry }> }) => remote.files.want(viewableItems.map((token) => token.item).filter(hasPreview), device),
    [remote, device],
  );

  const toggleSelecting = () => {
    if (selecting) setPicked(new Map());
    setSelecting(!selecting);
  };

  const pickedBytes = [...picked.values()].reduce((sum, entry) => sum + entry.size, 0);
  const entries = listing._tag === "loaded" ? listing.entries : [];

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <BackBar parent="Files" />
      <Title>{`${title}.`}</Title>
      <View style={styles.actions}>
        <Tap onPress={toggleSelecting} accessibilityRole="button" hitSlop={10}>
          <T v="medium" color={color.yellow}>
            {selecting ? "Done" : "Select"}
          </T>
        </Tap>
        {access.change && device === undefined ? (
          <Tap onPress={() => void putHere()} accessibilityRole="button" hitSlop={10}>
            <T v="medium" color={color.yellow}>
              Put files here
            </T>
          </Tap>
        ) : null}
      </View>
      <Segmented options={SORTS} value={sort} onChange={setSort} />
      {listing._tag === "loaded" && listing.total > FILES_PAGE ? <T v="mono" style={styles.count}>{`${listing.total.toLocaleString()} items`}</T> : null}
    </View>
  );

  const empty =
    listing._tag === "loading" ? <Empty title="Loading" /> : listing._tag === "failed" ? <Empty title="Can't open this folder" detail={listing.message} /> : <Empty title="Empty" />;

  return (
    <View style={styles.screen}>
      <LegendList
        data={entries}
        keyExtractor={(entry) => entry.path}
        renderItem={({ item }) => <EntryRow entry={item} now={now} selecting={selecting} selected={picked.has(item.path)} onPress={open} />}
        extraData={{ selecting, picked }}
        estimatedItemSize={52}
        recycleItems
        drawDistance={600}
        onEndReached={loadMore}
        onEndReachedThreshold={0.6}
        onViewableItemsChanged={onViewable}
        ListHeaderComponent={header}
        ListEmptyComponent={empty}
        ListFooterComponent={<View style={{ height: bottom + (picked.size > 0 ? 64 : 0) }} />}
        style={styles.screen}
      />
      {picked.size > 0 ? (
        <View style={[styles.bar, { bottom: bottom - 24 }]}>
          <T v="strong" color={color.bg} style={styles.barText}>{`${String(picked.size)} picked · ${formatBytes(pickedBytes)}`}</T>
          <Tap onPress={() => void get()} accessibilityRole="button" style={styles.barButton}>
            <T v="strong" color={color.yellow}>
              Get
            </T>
          </Tap>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: color.bg },
  actions: { flexDirection: "row", justifyContent: "space-between", paddingHorizontal: 20, paddingBottom: 12 },
  count: { paddingHorizontal: 20, paddingTop: 8 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 8, minHeight: 52 },
  picked: { backgroundColor: "rgba(242,236,107,0.06)" },
  rowText: { flex: 1 },
  icon: { width: 34, height: 34, borderRadius: 10 },
  iconTile: { backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  check: { width: 22, height: 22, borderRadius: 11, borderWidth: 1.5, borderColor: color.line2, alignItems: "center", justifyContent: "center" },
  checkOn: { backgroundColor: color.yellow, borderColor: color.yellow },
  bar: { position: "absolute", left: 14, right: 14, flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: color.ink, borderRadius: 18, paddingVertical: 10, paddingLeft: 16, paddingRight: 10 },
  barText: { flex: 1 },
  barButton: { backgroundColor: color.bg, borderRadius: 12, paddingVertical: 9, paddingHorizontal: 14 },
});
