import { LegendList } from "@legendapp/list/react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { FILES_PAGE, hasPreview } from "@vitals/app/state/files.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { FsEntry, FsSort } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { useCallback, useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { EntryRow } from "../FsRows.tsx";
import { pickFiles } from "../lib/clips.ts";
import { sendDrop } from "../lib/drops.ts";
import { useAccess } from "../lib/remote.ts";
import type { ControlStackParams } from "../navigation.ts";
import { macFileSheet } from "../sheets/MacFileSheet.tsx";
import { BackBar, color, Empty, Segmented, sheet, T, Tap, Title, toast, useDockSpace } from "../ui/index.ts";

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
      sheet.open(macFileSheet(entry, device === undefined ? null : { device, name: deviceName ?? "That phone" }));
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
        renderItem={({ item }) => <EntryRow entry={item} device={device} now={now} selecting={selecting} selected={picked.has(item.path)} onPress={open} />}
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
  bar: { position: "absolute", left: 14, right: 14, flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: color.ink, borderRadius: 18, paddingVertical: 10, paddingLeft: 16, paddingRight: 10 },
  barText: { flex: 1 },
  barButton: { backgroundColor: color.bg, borderRadius: 12, paddingVertical: 9, paddingHorizontal: 14 },
});
