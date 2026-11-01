import { LegendList } from "@legendapp/list/react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { type KindPage, mergeNewest } from "@vitals/app/state/files.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { FsEntry, FsRecentKind } from "@vitals/contracts";
import { useCallback, useEffect, useState } from "react";
import { StyleSheet, useWindowDimensions, View } from "react-native";
import Animated from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { FRESH_MS, RECENT_PAGE, recentKey, recentSeen, seeRecent } from "../lib/browseCache.ts";
import { EntryRow, Ghost, isGallery, KIND_TITLE, PhotoTile, SeenLine, SelectBar, SelectButton, type Since, useSeenFade, useSelection, whereOf } from "../FsRows.tsx";
import type { ControlStackParams } from "../navigation.ts";
import { fileSheet, transferSheet } from "../sheets/FsSheets.tsx";
import { ActionRow, BackBar, color, Empty, sheet, T, Title, useDockSpace } from "../ui/index.ts";

type Props = NativeStackScreenProps<ControlStackParams, "Recent">;


type Paged =
  | { readonly _tag: "loading" }
  | { readonly _tag: "failed"; readonly message: string }
  | { readonly _tag: "loaded"; readonly pages: ReadonlyArray<KindPage>; readonly busy: boolean; readonly since: Since | null };

/** What to show while asking again, or once asking failed: the remembered pages when there are some, current if just seen. */
const remembered = (key: string, failed: string | null = null): Paged => {
  const last = recentSeen.get(key);
  if (last !== undefined) return { _tag: "loaded", pages: last.pages, busy: false, since: failed === null && Date.now() - last.at < FRESH_MS ? null : { at: last.at, failed } };
  if (failed !== null) return { _tag: "failed", message: failed };
  return { _tag: "loading" };
};

const COLUMNS = 3;
const GAP = 4;
const EDGE = 16;

const rowsOf = (entries: ReadonlyArray<FsEntry>, size: number): ReadonlyArray<ReadonlyArray<FsEntry>> =>
  Array.from({ length: Math.ceil(entries.length / size) }, (_, index) => entries.slice(index * size, (index + 1) * size));

/** Everything of one kind on a device, newest first and paged: a grid for pictures, a list for files. Select, then Transfer. */
export function RecentScreen({ navigation, route }: Props) {
  const remote = useRemote();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(60_000);
  const { width } = useWindowDimensions();
  const { kind, source } = route.params;
  const device = source.device ?? undefined;
  const gallery = isGallery(kind);
  const key = recentKey(kind, device);
  const [paged, setPaged] = useState<Paged>(() => remembered(key));
  const selection = useSelection();

  const loadFirst = useCallback((live: () => boolean) => {
    const kinds: ReadonlyArray<FsRecentKind> = kind === "images" ? ["screenshots", "photos"] : [kind];
    void Promise.all(kinds.map(async (item): Promise<KindPage | string> => {
      const outcome = await remote.files.recent(item, 0, RECENT_PAGE, device);
      return outcome.ok ? { kind: item, entries: outcome.value.entries, more: outcome.value.more } : outcome.message;
    })).then((results) => {
      if (!live()) return;
      const pages = results.filter((result) => typeof result !== "string");
      const failure = results.find((result) => typeof result === "string");
      if (pages.length === 0) return setPaged(remembered(key, failure ?? "Nothing to show"));
      seeRecent(key, pages);
      setPaged({ _tag: "loaded", pages, busy: false, since: null });
      remote.files.want(mergeNewest(pages).entries.slice(0, 30), device);
    });
  }, [remote, kind, device, key]);

  useEffect(() => {
    let live = true;
    loadFirst(() => live);
    return () => {
      live = false;
    };
  }, [loadFirst]);

  const retry = () => {
    setPaged(remembered(key));
    loadFirst(() => true);
  };

  const loadMore = () => {
    if (paged._tag !== "loaded" || paged.busy || paged.since !== null) return;
    const { behind } = mergeNewest(paged.pages);
    if (behind.size === 0) return;
    setPaged({ ...paged, busy: true });
    void Promise.all(
      paged.pages.map(async (page, index): Promise<KindPage> => {
        if (!behind.has(index)) return page;
        const outcome = await remote.files.recent(page.kind, page.entries.length, RECENT_PAGE, device);
        return outcome.ok ? { ...page, entries: [...page.entries, ...outcome.value.entries], more: outcome.value.more } : { ...page, more: false };
      }),
    ).then((pages) => setPaged((current) => (current._tag === "loaded" ? { _tag: "loaded", pages, busy: false, since: null } : current)));
  };

  const entries = paged._tag === "loaded" ? mergeNewest(paged.pages).entries : [];
  const since = paged._tag === "loaded" ? paged.since : null;
  const fade = useSeenFade(since !== null);
  const open = (entry: FsEntry) => (selection.selecting ? selection.toggle(entry) : navigation.push("Preview", { entry, source, parent: KIND_TITLE[kind], siblings: entries }));
  const showSheet = (entry: FsEntry) => sheet.open(fileSheet(entry, source));

  const onViewable = useCallback(
    ({ viewableItems }: { readonly viewableItems: ReadonlyArray<{ readonly item: ReadonlyArray<FsEntry> }> }) => remote.files.want(viewableItems.flatMap((token) => token.item), device),
    [remote, device],
  );

  const rows = rowsOf(entries, gallery ? COLUMNS : 1);

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <View style={styles.top}>
        <BackBar parent={source.name} />
        {entries.length > 0 ? <SelectButton selecting={selection.selecting} onPress={selection.selecting ? selection.stop : selection.start} /> : null}
      </View>
      <Title>{`${KIND_TITLE[kind]}.`}</Title>
      <T v="small" style={styles.sub}>{`On ${whereOf(source)} · newest first`}</T>
      <SeenLine since={since} now={now} onRetry={retry} />
    </View>
  );

  const size = Math.floor((width - EDGE * 2 - GAP * (COLUMNS - 1)) / COLUMNS);
  const empty = {
    loading: <Ghost gallery={gallery} size={size} gap={GAP} />,
    failed: (
      <>
        <Empty title={`Can't see ${whereOf(source)}`} detail={paged._tag === "failed" ? paged.message : undefined} />
        <ActionRow icon="restart" label="Try again" onPress={retry} />
      </>
    ),
    loaded: <Empty title="Nothing yet" />,
  }[paged._tag];

  return (
    <View style={styles.screen}>
      <LegendList
        key={gallery ? "grid" : "list"}
        data={rows}
        keyExtractor={(row) => row[0]?.path ?? ""}
        renderItem={({ item }) =>
          gallery ? (
            <Animated.View style={[styles.gridRow, { height: size }, fade]}>
              {item.map((entry) => (
                <PhotoTile key={entry.path} entry={entry} device={source.device} size={size} selecting={selection.selecting} selected={selection.picked.has(entry.path)} onPress={open} onLongPress={showSheet} />
              ))}
            </Animated.View>
          ) : (
            <Animated.View style={fade}>
              {item.map((entry) => (
                <EntryRow key={entry.path} entry={entry} device={source.device} now={now} selecting={selection.selecting} selected={selection.picked.has(entry.path)} onPress={open} onLongPress={showSheet} />
              ))}
            </Animated.View>
          )
        }
        extraData={selection}
        getFixedItemSize={() => (gallery ? size + GAP : undefined)}
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
