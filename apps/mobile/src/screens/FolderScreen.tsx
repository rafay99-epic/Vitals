import { LegendList } from "@legendapp/list/react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { FILES_PAGE } from "@vitals/app/state/files.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { FsEntry } from "@vitals/contracts";
import { Fragment, useCallback, useEffect, useState } from "react";
import { StyleSheet, useWindowDimensions, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { EntryRow, isFolder, isPicture, PhotoTile, SelectBar, SelectButton, useSelection } from "../FsRows.tsx";
import { pickFiles } from "../lib/clips.ts";
import { sendDrop } from "../lib/drops.ts";
import { useAccess } from "../lib/remote.ts";
import type { ControlStackParams } from "../navigation.ts";
import { fileSheet, transferSheet } from "../sheets/FsSheets.tsx";
import { ActionRow, BackBar, color, Empty, sheet, T, Tap, Title, toast, useDockSpace } from "../ui/index.ts";

type Props = NativeStackScreenProps<ControlStackParams, "Folder">;

/** A list line: one folder or file, or a row of three pictures. */
type Line = { readonly _tag: "entry"; readonly entry: FsEntry } | { readonly _tag: "pictures"; readonly entries: ReadonlyArray<FsEntry> };

type Listing =
  | { readonly _tag: "loading" }
  | { readonly _tag: "failed"; readonly message: string }
  | { readonly _tag: "loaded"; readonly count: number; readonly lines: ReadonlyArray<Line>; readonly total: number; readonly busy: boolean };

const COLUMNS = 3;
const GAP = 4;
const EDGE = 16;

/**
 * One page as lines: folders first, then pictures three to a row, then every other file. Pages only ever
 * add lines below, so a page landing never moves what's already on screen.
 */
const linesOf = (entries: ReadonlyArray<FsEntry>): ReadonlyArray<Line> => {
  const pictures = entries.filter(isPicture);
  return [
    ...entries.filter(isFolder).map((entry): Line => ({ _tag: "entry", entry })),
    ...Array.from({ length: Math.ceil(pictures.length / COLUMNS) }, (_, index): Line => ({ _tag: "pictures", entries: pictures.slice(index * COLUMNS, (index + 1) * COLUMNS) })),
    ...entries.filter((entry) => !isFolder(entry) && !isPicture(entry)).map((entry): Line => ({ _tag: "entry", entry })),
  ];
};

/** The files in a page, in the order they show: pictures, then everything else. */
const filesOf = (lines: ReadonlyArray<Line>): ReadonlyArray<FsEntry> => lines.flatMap((line) => (line._tag === "pictures" ? line.entries : isFolder(line.entry) ? [] : [line.entry]));

const keyOf = (line: Line): string => (line._tag === "entry" ? line.entry.path : `pictures:${line.entries[0]?.path ?? ""}`);

const typeOf = (line: Line): Line["_tag"] => line._tag;

/** The path under the title. Each part goes back to that folder; the first goes back to the device's page. */
function Crumbs({ parts, onPick }: { readonly parts: ReadonlyArray<string>; readonly onPick: (index: number) => void }) {
  return (
    <View style={styles.crumbs}>
      {parts.map((part, index) => {
        const last = index === parts.length - 1;
        return (
          <Fragment key={parts.slice(0, index + 1).join("/")}>
            {index > 0 ? <T v="small">›</T> : null}
            {last ? (
              <T v="small" color={color.ink}>
                {part}
              </T>
            ) : (
              <Tap onPress={() => onPick(index)} accessibilityRole="button" accessibilityLabel={`Go to ${part}`} hitSlop={8}>
                <T v="small" color={color.ink2}>
                  {part}
                </T>
              </Tap>
            )}
          </Fragment>
        );
      })}
    </View>
  );
}

function EmptyFolder({ listing }: { readonly listing: Listing }) {
  if (listing._tag === "loading") return <Empty title="Loading" />;
  if (listing._tag === "failed") return <Empty title="Can't open this folder" detail={listing.message} />;
  return <Empty title="Empty" />;
}

/** A folder on the Mac or a phone, as deep as it goes. Select, then Transfer. */
export function FolderScreen({ navigation, route }: Props) {
  const remote = useRemote();
  const access = useAccess();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(60_000);
  const { width } = useWindowDimensions();
  const { path, source, trail } = route.params;
  const device = source.device ?? undefined;
  const title = trail.at(-1) ?? source.name;
  const [listing, setListing] = useState<Listing>({ _tag: "loading" });
  const selection = useSelection();

  useEffect(() => {
    let cancelled = false;
    void remote.files.list(path, "name", 0, device).then((outcome) => {
      if (cancelled) return;
      setListing(outcome.ok ? { _tag: "loaded", count: outcome.value.entries.length, lines: linesOf(outcome.value.entries), total: outcome.value.total, busy: false } : { _tag: "failed", message: outcome.message });
      if (outcome.ok) remote.files.want([...outcome.value.entries.filter(isPicture).slice(0, 24), ...outcome.value.entries.filter((entry) => !isPicture(entry)).slice(0, 24)], device);
    });
    return () => {
      cancelled = true;
    };
  }, [remote, path, device]);

  const loadMore = () => {
    if (listing._tag !== "loaded" || listing.busy || listing.count >= listing.total) return;
    const offset = listing.count;
    setListing({ ...listing, busy: true });
    void remote.files.list(path, "name", offset, device).then((outcome) => {
      setListing((current) => {
        if (current._tag !== "loaded" || current.count !== offset) return current;
        if (!outcome.ok || outcome.value.entries.length === 0) return { ...current, busy: false, total: offset };
        return { _tag: "loaded", count: offset + outcome.value.entries.length, lines: [...current.lines, ...linesOf(outcome.value.entries)], total: outcome.value.total, busy: false };
      });
    });
  };

  const lines = listing._tag === "loaded" ? listing.lines : [];
  const open = (entry: FsEntry) => {
    if (isFolder(entry)) navigation.push("Folder", { path: entry.path, source, trail: [...trail, entry.name] });
    else if (selection.selecting) selection.toggle(entry);
    else navigation.push("Preview", { entry, source, parent: title, siblings: filesOf(lines) });
  };

  const showSheet = (entry: FsEntry) => sheet.open(fileSheet(entry, source));

  const putHere = async () => {
    const batch = await pickFiles();
    if (batch === null) return;
    if (await sendDrop(remote, batch, { dest: path })) toast.show(`Sending ${batch.label} to ${title} on your Mac`);
  };

  const onViewable = useCallback(
    ({ viewableItems }: { readonly viewableItems: ReadonlyArray<{ readonly item: Line }> }) =>
      remote.files.want(
        viewableItems.flatMap((token) => (token.item._tag === "entry" ? [token.item.entry] : token.item.entries)),
        device,
      ),
    [remote, device],
  );

  const size = Math.floor((width - EDGE * 2 - GAP * (COLUMNS - 1)) / COLUMNS);
  const crumbs = [source.name, ...trail];
  const hasFiles = lines.some((line) => line._tag === "pictures" || !isFolder(line.entry));

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <View style={styles.top}>
        <BackBar parent={crumbs.at(-2) ?? source.name} />
        {hasFiles ? <SelectButton selecting={selection.selecting} onPress={selection.selecting ? selection.stop : selection.start} /> : null}
      </View>
      <Title>{`${title}.`}</Title>
      <Crumbs parts={crumbs} onPick={(index) => navigation.pop(crumbs.length - 1 - index)} />
    </View>
  );

  const footer = (
    <View style={{ paddingBottom: bottom + (selection.selecting ? 64 : 0) }}>
      {listing._tag === "loaded" && listing.total > FILES_PAGE ? <T v="mono" style={styles.count}>{`${listing.total.toLocaleString()} items`}</T> : null}
      {access.change && source.device === null && listing._tag === "loaded" && !selection.selecting ? <ActionRow icon="plus" label="Put files here" detail={`From this phone into ${title}`} onPress={() => void putHere()} /> : null}
    </View>
  );

  return (
    <View style={styles.screen}>
      <LegendList
        data={lines}
        keyExtractor={keyOf}
        getItemType={typeOf}
        getFixedItemSize={(line) => (line._tag === "pictures" ? size + GAP : undefined)}
        renderItem={({ item }) =>
          item._tag === "entry" ? (
            <EntryRow entry={item.entry} device={source.device} now={now} selecting={selection.selecting} selected={selection.picked.has(item.entry.path)} onPress={open} onLongPress={showSheet} />
          ) : (
            <View style={[styles.gridRow, { height: size }]}>
              {item.entries.map((entry) => (
                <PhotoTile key={entry.path} entry={entry} device={source.device} size={size} selecting={selection.selecting} selected={selection.picked.has(entry.path)} onPress={open} onLongPress={showSheet} />
              ))}
            </View>
          )
        }
        extraData={selection}
        estimatedItemSize={52}
        recycleItems
        drawDistance={600}
        onEndReached={loadMore}
        onEndReachedThreshold={0.6}
        onViewableItemsChanged={onViewable}
        ListHeaderComponent={header}
        ListEmptyComponent={<EmptyFolder listing={listing} />}
        ListFooterComponent={footer}
        style={styles.screen}
      />
      {selection.selecting ? <SelectBar count={selection.picked.size} bottom={bottom - 24} onTransfer={() => sheet.open(transferSheet([...selection.picked.values()], source, selection.stop))} /> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: color.bg },
  top: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" },
  crumbs: { flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 5, paddingHorizontal: 20, paddingBottom: 14, marginTop: -8 },
  count: { paddingHorizontal: 20, paddingVertical: 8 },
  gridRow: { flexDirection: "row", gap: GAP, paddingHorizontal: EDGE, marginVertical: GAP / 2 },
});
