import { LegendList } from "@legendapp/list/react-native";
import type { File } from "expo-file-system";
import { useEffect, useMemo, useState } from "react";
import { type LayoutChangeEvent, ScrollView, StyleSheet, View } from "react-native";

import { readWorkbook } from "../lib/preview.ts";
import { SHEET_ROWS, type SheetRows, type Workbook } from "../lib/sheet.ts";
import { color, Empty, T, Tap } from "../ui/index.ts";

type Book = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly book: Workbook };

const ROW = 30;
const GUTTER = 40;
const CHAR = 7.4;
const MIN_WIDTH = 56;
const MAX_WIDTH = 220;
/** Rows looked at to size the columns. */
const SAMPLE = 200;

/** A column wide enough for its longest value, within limits. Markdown tables size theirs the same way. */
export const columnWidth = (longest: number): number => Math.round(Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, longest * CHAR + 16)));

/** Each column as wide as its longest value in the first rows. */
const widthsOf = (sheet: SheetRows): ReadonlyArray<{ readonly id: number; readonly width: number }> =>
  Array.from({ length: sheet.columns }, (_, id) => ({ id, width: columnWidth(Math.max(0, ...sheet.rows.slice(0, SAMPLE).map((row) => (row[id] ?? "").length))) }));

const keyOf = (_row: ReadonlyArray<string>, index: number): string => String(index);

/** One sheet as a grid: row numbers on the left, every cell on one line. Scrolls both ways. */
function Grid({ sheet, bottom }: { readonly sheet: SheetRows; readonly bottom: number }) {
  const widths = useMemo(() => widthsOf(sheet), [sheet]);
  const [height, setHeight] = useState(0);
  const width = GUTTER + widths.reduce((sum, column) => sum + column.width, 0);
  const measure = (event: LayoutChangeEvent) => setHeight(event.nativeEvent.layout.height);
  if (sheet.rows.length === 0) return <Empty title="Empty" />;
  return (
    <View style={styles.fill} onLayout={measure}>
      <ScrollView horizontal nestedScrollEnabled showsHorizontalScrollIndicator={false}>
        <View style={{ width, height }}>
          <LegendList
            data={sheet.rows}
            keyExtractor={keyOf}
            getFixedItemSize={() => ROW}
            estimatedItemSize={ROW}
            renderItem={({ item, index }) => (
              <View style={styles.row}>
                <T v="mono" color={color.mute} style={[styles.cell, { width: GUTTER }]}>
                  {String(index + 1)}
                </T>
                {widths.map((column) => (
                  <T key={column.id} v="mono" color={color.ink2} numberOfLines={1} style={[styles.cell, styles.border, { width: column.width }]}>
                    {item[column.id] ?? ""}
                  </T>
                ))}
              </View>
            )}
            ListFooterComponent={
              <View style={{ paddingBottom: bottom }}>
                {sheet.cut ? (
                  <T v="small" style={styles.note}>
                    {`Showing the first ${SHEET_ROWS.toLocaleString()} rows and 60 columns`}
                  </T>
                ) : null}
              </View>
            }
            style={styles.fill}
          />
        </View>
      </ScrollView>
    </View>
  );
}

/** A spreadsheet: a tab per sheet when there's more than one, then the picked sheet as a grid. */
export function SheetViewer({ file, bottom }: { readonly file: File; readonly bottom: number }) {
  const [book, setBook] = useState<Book>({ _tag: "loading" });
  const [picked, setPicked] = useState(0);

  useEffect(() => {
    let gone = false;
    readWorkbook(file)
      .then((read) => !gone && setBook({ _tag: "loaded", book: read }))
      .catch((cause: unknown) => !gone && setBook({ _tag: "failed", message: cause instanceof Error ? cause.message : "This file didn't open" }));
    return () => {
      gone = true;
    };
  }, [file]);

  const sheet = useMemo(() => (book._tag === "loaded" ? book.book.sheet(picked) : null), [book, picked]);

  if (book._tag === "loading") return <Empty title="Opening" />;
  if (book._tag === "failed") return <Empty title="Can't show this file" detail={book.message} />;
  return (
    <View style={styles.fill}>
      {book.book.names.length > 1 ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.tabs}>
          {book.book.names.map((name, index) => (
            <Tap key={`${name}${String(index)}`} onPress={() => setPicked(index)} accessibilityRole="tab" accessibilityState={{ selected: index === picked }} hitSlop={6}>
              <T v="strong" color={index === picked ? color.ink : color.mute}>
                {name}
              </T>
            </Tap>
          ))}
        </ScrollView>
      ) : null}
      {sheet === null ? null : <Grid key={picked} sheet={sheet} bottom={bottom} />}
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  tabs: { gap: 18, paddingHorizontal: 20, paddingBottom: 12 },
  row: { flexDirection: "row", height: ROW, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: color.line2 },
  cell: { paddingHorizontal: 8, lineHeight: ROW },
  border: { borderLeftWidth: StyleSheet.hairlineWidth, borderColor: color.line2 },
  note: { paddingHorizontal: 16, paddingTop: 12 },
});
