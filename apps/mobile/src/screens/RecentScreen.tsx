import { LegendList } from "@legendapp/list/react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { FsEntry } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { useCallback, useEffect, useState } from "react";
import { StyleSheet, useWindowDimensions, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { EntryRow, isGallery, KIND_TITLE, PhotoTile } from "../FsRows.tsx";
import { getFromMac } from "../lib/drops.ts";
import type { ControlStackParams } from "../navigation.ts";
import { macFileSheet } from "../sheets/MacFileSheet.tsx";
import { BackBar, color, Empty, sheet, T, Tap, Title, toast, useDockSpace } from "../ui/index.ts";

type Props = NativeStackScreenProps<ControlStackParams, "Recent">;

type Page = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly entries: ReadonlyArray<FsEntry>; readonly more: boolean; readonly busy: boolean };

const PAGE = 60;
const COLUMNS = 3;
const GAP = 6;
const EDGE = 16;

const rowsOf = (entries: ReadonlyArray<FsEntry>, size: number): ReadonlyArray<ReadonlyArray<FsEntry>> =>
  Array.from({ length: Math.ceil(entries.length / size) }, (_, index) => entries.slice(index * size, (index + 1) * size));

/** "See all" for one kind on one device: a grid for pictures, a list for files, newest first. Hold to pick several. */
export function RecentScreen({ route }: Props) {
  const remote = useRemote();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(60_000);
  const { width } = useWindowDimensions();
  const { kind, device, deviceName } = route.params;
  const gallery = isGallery(kind);
  const where = deviceName ?? "your Mac";
  const [page, setPage] = useState<Page>({ _tag: "loading" });
  const [selecting, setSelecting] = useState(false);
  const [picked, setPicked] = useState<ReadonlyMap<string, FsEntry>>(new Map());

  useEffect(() => {
    let cancelled = false;
    void remote.files.recent(kind, 0, PAGE, device).then((outcome) => {
      if (cancelled) return;
      setPage(outcome.ok ? { _tag: "loaded", entries: outcome.value.entries, more: outcome.value.more, busy: false } : { _tag: "failed", message: outcome.message });
      if (outcome.ok) remote.files.want(outcome.value.entries.slice(0, 30), device);
    });
    return () => {
      cancelled = true;
    };
  }, [remote, kind, device]);

  const loadMore = () => {
    if (page._tag !== "loaded" || !page.more || page.busy) return;
    const shown = page.entries;
    setPage({ ...page, busy: true });
    void remote.files.recent(kind, shown.length, PAGE, device).then((outcome) =>
      setPage((current) =>
        current._tag !== "loaded" ? current : outcome.ok ? { _tag: "loaded", entries: [...shown, ...outcome.value.entries], more: outcome.value.more, busy: false } : { ...current, busy: false, more: false },
      ),
    );
  };

  const toggle = (entry: FsEntry) =>
    setPicked((current) => {
      const next = new Map(current);
      if (next.has(entry.path)) next.delete(entry.path);
      else next.set(entry.path, entry);
      return next;
    });

  const open = (entry: FsEntry) => {
    if (selecting) return toggle(entry);
    sheet.open(macFileSheet(entry, device === undefined ? null : { device, name: where }));
  };

  const hold = (entry: FsEntry) => {
    if (!selecting) setSelecting(true);
    toggle(entry);
  };

  const stopSelecting = () => {
    setSelecting(false);
    setPicked(new Map());
  };

  const get = async () => {
    const entries = [...picked.values()];
    stopSelecting();
    const what = entries.length === 1 ? (entries[0]?.name ?? "it") : `${String(entries.length)} files`;
    const paths = entries.map((entry) => entry.path);
    if (device !== undefined) {
      const outcome = await remote.files.pull(device, paths);
      toast.show(outcome.ok ? `${where} is sending ${what} through your Mac` : outcome.message, { tone: outcome.ok ? "ok" : "bad" });
      return;
    }
    if (await getFromMac(remote, paths)) toast.show(`Getting ${what} from your Mac`);
  };

  const onViewable = useCallback(
    ({ viewableItems }: { readonly viewableItems: ReadonlyArray<{ readonly item: ReadonlyArray<FsEntry> }> }) => remote.files.want(viewableItems.flatMap((token) => token.item), device),
    [remote, device],
  );

  const size = Math.floor((width - EDGE * 2 - GAP * (COLUMNS - 1)) / COLUMNS);
  const entries = page._tag === "loaded" ? page.entries : [];
  const rows = rowsOf(entries, gallery ? COLUMNS : 1);
  const pickedBytes = [...picked.values()].reduce((sum, entry) => sum + entry.size, 0);

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <BackBar parent="Files" />
      <Title>{`${KIND_TITLE[kind]}.`}</Title>
      <View style={styles.actions}>
        <T v="small">{`On ${where} · newest first`}</T>
        {entries.length > 0 ? (
          <Tap onPress={selecting ? stopSelecting : () => setSelecting(true)} accessibilityRole="button" hitSlop={10}>
            <T v="medium" color={color.yellow}>
              {selecting ? "Done" : "Select"}
            </T>
          </Tap>
        ) : null}
      </View>
    </View>
  );

  const empty = page._tag === "loading" ? <Empty title="Loading" /> : page._tag === "failed" ? <Empty title={`Can't see ${where}`} detail={page.message} /> : <Empty title="Nothing yet" />;

  return (
    <View style={styles.screen}>
      <LegendList
        key={gallery ? "grid" : "list"}
        data={rows}
        keyExtractor={(row) => row[0]?.path ?? ""}
        renderItem={({ item }) =>
          gallery ? (
            <View style={styles.gridRow}>
              {item.map((entry) => (
                <PhotoTile key={entry.path} entry={entry} device={device} size={size} selecting={selecting} selected={picked.has(entry.path)} onPress={open} onLongPress={hold} />
              ))}
            </View>
          ) : (
            <>
              {item.map((entry) => (
                <EntryRow key={entry.path} entry={entry} device={device} now={now} selecting={selecting} selected={picked.has(entry.path)} onPress={open} onLongPress={hold} />
              ))}
            </>
          )
        }
        extraData={{ selecting, picked }}
        estimatedItemSize={gallery ? size + GAP : 52}
        recycleItems
        drawDistance={800}
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
              {`Get ${String(picked.size)}`}
            </T>
          </Tap>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: color.bg },
  actions: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", paddingHorizontal: 20, paddingBottom: 12 },
  gridRow: { flexDirection: "row", gap: GAP, paddingHorizontal: EDGE, marginBottom: GAP },
  bar: { position: "absolute", left: 14, right: 14, flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: color.ink, borderRadius: 18, paddingVertical: 10, paddingLeft: 16, paddingRight: 10 },
  barText: { flex: 1 },
  barButton: { backgroundColor: color.bg, borderRadius: 12, paddingVertical: 9, paddingHorizontal: 14 },
});
