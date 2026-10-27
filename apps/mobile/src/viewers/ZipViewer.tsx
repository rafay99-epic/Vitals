import { LegendList } from "@legendapp/list/react-native";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { FsEntry } from "@vitals/contracts";
import type { File } from "expo-file-system";
import { useEffect, useRef, useState } from "react";
import { StyleSheet, View } from "react-native";

import { EntryRow } from "../FsRows.tsx";
import { listZip, unzipEntry } from "../lib/preview.ts";
import { baseName, childrenOf, type ZipEntry } from "../lib/zip.ts";
import { color, Empty, Icon, T, Tap, toast } from "../ui/index.ts";

type Listing = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly entries: ReadonlyArray<ZipEntry> };

/** A zip entry as a file row. Only the name, kind, size and date are real; nothing looks it up by path. */
const rowOf = (entry: ZipEntry): FsEntry => ({ name: baseName(entry), path: `/${entry.name.replace(/\/$/, "")}`, kind: entry.folder ? "folder" : "file", size: entry.size, modifiedAt: entry.modifiedAt });

/** What's inside a cached zip, one folder level at a time. Tapping a file unpacks just that one and hands it to `onOpen`. */
export function ZipViewer({ file, bottom, onOpen }: { readonly file: File; readonly bottom: number; readonly onOpen: (entry: FsEntry, unpacked: File) => void }) {
  const now = useNow(60_000);
  const [listing, setListing] = useState<Listing>({ _tag: "loading" });
  const [prefix, setPrefix] = useState("");
  const [unpacking, setUnpacking] = useState<string | null>(null);
  const gone = useRef(false);

  useEffect(() => {
    gone.current = false;
    listZip(file)
      .then((entries) => !gone.current && setListing({ _tag: "loaded", entries }))
      .catch((cause: unknown) => !gone.current && setListing({ _tag: "failed", message: cause instanceof Error ? cause.message : "This zip didn't open" }));
    return () => {
      gone.current = true;
    };
  }, [file]);

  if (listing._tag === "loading") return <Empty title="Opening" />;
  if (listing._tag === "failed") return <Empty title="Can't show this zip" detail={listing.message} />;

  const shown = childrenOf(listing.entries, prefix);
  const byPath = new Map(shown.map((entry) => [rowOf(entry).path, entry] as const));
  const up = prefix.split("/").slice(0, -2);

  const open = (row: FsEntry) => {
    const entry = byPath.get(row.path);
    if (entry === undefined || unpacking !== null) return;
    if (entry.folder) return setPrefix(entry.name);
    setUnpacking(row.name);
    unzipEntry(file, entry, () => gone.current)
      .then((unpacked) => unpacked !== null && onOpen(row, unpacked))
      .catch((cause: unknown) => toast.show(cause instanceof Error ? cause.message : "That file didn't unpack", { tone: "bad" }))
      .finally(() => !gone.current && setUnpacking(null));
  };

  const header = (
    <>
      {prefix === "" ? null : (
        <Tap onPress={() => setPrefix(up.length === 0 ? "" : `${up.join("/")}/`)} accessibilityRole="button" accessibilityLabel="Up one folder" style={styles.up}>
          <Icon name="back" size={14} color={color.yellow} weight={2.4} />
          <T v="medium" color={color.yellow} numberOfLines={1}>
            {up.at(-1) ?? file.name}
          </T>
        </Tap>
      )}
      <T v="small" style={styles.count}>
        {unpacking === null ? `${String(shown.length)} ${shown.length === 1 ? "item" : "items"}${prefix === "" ? "" : ` in ${prefix.slice(0, -1).split("/").at(-1) ?? ""}`}` : `Unpacking ${unpacking}`}
      </T>
    </>
  );

  return (
    <LegendList
      data={shown.map(rowOf)}
      keyExtractor={(row) => row.path}
      renderItem={({ item }) => <EntryRow entry={item} device={null} now={now} onPress={open} />}
      extraData={prefix}
      estimatedItemSize={52}
      recycleItems
      ListHeaderComponent={header}
      ListEmptyComponent={<Empty title="Empty" />}
      ListFooterComponent={<View style={{ height: bottom }} />}
      style={styles.list}
    />
  );
}

const styles = StyleSheet.create({
  list: { flex: 1 },
  up: { flexDirection: "row", alignItems: "center", gap: 6, paddingHorizontal: 20, paddingVertical: 8 },
  count: { paddingHorizontal: 20, paddingBottom: 6 },
});
