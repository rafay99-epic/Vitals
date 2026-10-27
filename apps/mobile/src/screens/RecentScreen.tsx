import { LegendList } from "@legendapp/list/react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { mergeNewest, type RecentPage } from "@vitals/app/state/files.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { FsEntry, FsRecentKind } from "@vitals/contracts";
import { useCallback, useEffect, useState } from "react";
import { StyleSheet, useWindowDimensions, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { EntryRow, isGallery, KIND_TITLE, PhotoTile, SelectBar, SelectButton, useSelection, whereOf } from "../FsRows.tsx";
import type { ControlStackParams } from "../navigation.ts";
import { fileSheet, transferSheet } from "../sheets/FsSheets.tsx";
import { BackBar, color, Empty, sheet, T, Title, useDockSpace } from "../ui/index.ts";

type Props = NativeStackScreenProps<ControlStackParams, "Recent">;

interface KindPage extends RecentPage {
  readonly kind: FsRecentKind;
}

type Paged = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly pages: ReadonlyArray<KindPage>; readonly busy: boolean };

const PAGE = 60;
const COLUMNS = 3;
const GAP = 4;
const EDGE = 16;

const rowsOf = (entries: ReadonlyArray<FsEntry>, size: number): ReadonlyArray<ReadonlyArray<FsEntry>> =>
  Array.from({ length: Math.ceil(entries.length / size) }, (_, index) => entries.slice(index * size, (index + 1) * size));

/** Everything of one kind on a device, newest first and paged: a grid for pictures, a list for files. Select, then Transfer. */
export function RecentScreen({ route }: Props) {
  const remote = useRemote();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(60_000);
  const { width } = useWindowDimensions();
  const { kind, source } = route.params;
  const device = source.device ?? undefined;
  const gallery = isGallery(kind);
  const [paged, setPaged] = useState<Paged>({ _tag: "loading" });
  const selection = useSelection();

  useEffect(() => {
    let cancelled = false;
    const kinds: ReadonlyArray<FsRecentKind> = kind === "images" ? ["screenshots", "photos"] : [kind];
    void Promise.all(kinds.map(async (item): Promise<KindPage | string> => {
      const outcome = await remote.files.recent(item, 0, PAGE, device);
      return outcome.ok ? { kind: item, entries: outcome.value.entries, more: outcome.value.more } : outcome.message;
    })).then((results) => {
      if (cancelled) return;
      const pages = results.filter((result) => typeof result !== "string");
      const failure = results.find((result) => typeof result === "string");
      if (pages.length === 0) return setPaged({ _tag: "failed", message: failure ?? "Nothing to show" });
      setPaged({ _tag: "loaded", pages, busy: false });
      remote.files.want(mergeNewest(pages).entries.slice(0, 30), device);
    });
    return () => {
      cancelled = true;
    };
  }, [remote, kind, device]);

  const loadMore = () => {
    if (paged._tag !== "loaded" || paged.busy) return;
    const { behind } = mergeNewest(paged.pages);
    if (behind.size === 0) return;
    setPaged({ ...paged, busy: true });
    void Promise.all(
      paged.pages.map(async (page, index): Promise<KindPage> => {
        if (!behind.has(index)) return page;
        const outcome = await remote.files.recent(page.kind, page.entries.length, PAGE, device);
        return outcome.ok ? { ...page, entries: [...page.entries, ...outcome.value.entries], more: outcome.value.more } : { ...page, more: false };
      }),
    ).then((pages) => setPaged((current) => (current._tag === "loaded" ? { _tag: "loaded", pages, busy: false } : current)));
  };

  const open = (entry: FsEntry) => (selection.selecting ? selection.toggle(entry) : sheet.open(fileSheet(entry, source)));

  const onViewable = useCallback(
    ({ viewableItems }: { readonly viewableItems: ReadonlyArray<{ readonly item: ReadonlyArray<FsEntry> }> }) => remote.files.want(viewableItems.flatMap((token) => token.item), device),
    [remote, device],
  );

  const size = Math.floor((width - EDGE * 2 - GAP * (COLUMNS - 1)) / COLUMNS);
  const entries = paged._tag === "loaded" ? mergeNewest(paged.pages).entries : [];
  const rows = rowsOf(entries, gallery ? COLUMNS : 1);

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <View style={styles.top}>
        <BackBar parent={source.name} />
        {entries.length > 0 ? <SelectButton selecting={selection.selecting} onPress={selection.selecting ? selection.stop : selection.start} /> : null}
      </View>
      <Title>{`${KIND_TITLE[kind]}.`}</Title>
      <T v="small" style={styles.sub}>{`On ${whereOf(source)} · newest first`}</T>
    </View>
  );

  const empty = paged._tag === "loading" ? <Empty title="Loading" /> : paged._tag === "failed" ? <Empty title={`Can't see ${whereOf(source)}`} detail={paged.message} /> : <Empty title="Nothing yet" />;

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
                <PhotoTile key={entry.path} entry={entry} device={source.device} size={size} selecting={selection.selecting} selected={selection.picked.has(entry.path)} onPress={open} />
              ))}
            </View>
          ) : (
            <>
              {item.map((entry) => (
                <EntryRow key={entry.path} entry={entry} device={source.device} now={now} selecting={selection.selecting} selected={selection.picked.has(entry.path)} onPress={open} />
              ))}
            </>
          )
        }
        extraData={selection}
        estimatedItemSize={gallery ? size + GAP : 52}
        recycleItems
        drawDistance={800}
        onEndReached={loadMore}
        onEndReachedThreshold={0.6}
        onViewableItemsChanged={onViewable}
        ListHeaderComponent={header}
        ListEmptyComponent={empty}
        ListFooterComponent={<View style={{ height: bottom + (selection.selecting ? 64 : 0) }} />}
        style={styles.screen}
      />
      {selection.selecting ? <SelectBar count={selection.picked.size} bottom={bottom - 24} onTransfer={() => sheet.open(transferSheet([...selection.picked.values()], source, selection.stop))} /> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: color.bg },
  top: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" },
  sub: { paddingHorizontal: 20, paddingBottom: 12, marginTop: -8 },
  gridRow: { flexDirection: "row", gap: GAP, paddingHorizontal: EDGE, marginBottom: GAP },
});
