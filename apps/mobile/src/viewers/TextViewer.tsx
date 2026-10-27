import { LegendList } from "@legendapp/list/react-native";
import type { File } from "expo-file-system";
import { useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";

import { readText } from "../lib/preview.ts";
import { color, Empty, T } from "../ui/index.ts";

/** Lines per list item: enough to select a paragraph, few enough that only nearby text renders. */
const BLOCK = 40;

type Text = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly blocks: ReadonlyArray<string>; readonly cut: boolean };

const blocksOf = (text: string): ReadonlyArray<string> => {
  const lines = text.split("\n");
  return Array.from({ length: Math.ceil(lines.length / BLOCK) }, (_, index) => lines.slice(index * BLOCK, (index + 1) * BLOCK).join("\n"));
};

const keyOf = (_block: string, index: number): string => String(index);

/** The start of a text file in monospace, selectable, in blocks of lines so a long file scrolls smoothly. */
export function TextViewer({ file, bottom }: { readonly file: File; readonly bottom: number }) {
  const [text, setText] = useState<Text>({ _tag: "loading" });

  useEffect(() => {
    let gone = false;
    readText(file)
      .then(({ text: read, cut }) => !gone && setText({ _tag: "loaded", blocks: blocksOf(read), cut }))
      .catch((cause: unknown) => !gone && setText({ _tag: "failed", message: cause instanceof Error ? cause.message : "This file didn't open" }));
    return () => {
      gone = true;
    };
  }, [file]);

  if (text._tag === "loading") return <Empty title="Opening" />;
  if (text._tag === "failed") return <Empty title="Can't show this file" detail={text.message} />;
  return (
    <LegendList
      data={text.blocks}
      keyExtractor={keyOf}
      renderItem={({ item }) => (
        <T v="mono" color={color.ink2} selectable style={styles.block}>
          {item}
        </T>
      )}
      estimatedItemSize={BLOCK * 16}
      ListHeaderComponent={text.cut ? <T v="small" style={styles.cut}>Showing the first 256 KB</T> : null}
      ListFooterComponent={<View style={{ height: bottom }} />}
      style={styles.list}
    />
  );
}

const styles = StyleSheet.create({
  list: { flex: 1 },
  block: { paddingHorizontal: 16 },
  cut: { paddingHorizontal: 16, paddingBottom: 10 },
});
