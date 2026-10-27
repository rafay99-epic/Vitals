import { LegendList } from "@legendapp/list/react-native";
import type { File } from "expo-file-system";
import type { MarkedToken, Token, Tokens } from "marked";
import { type ReactNode, useEffect, useState } from "react";
import { Linking, ScrollView, StyleSheet, Text, View } from "react-native";

import { markdownBlocks } from "../lib/markdown.ts";
import { readText } from "../lib/preview.ts";
import { unescape } from "../lib/sheet.ts";
import { color, Empty, font, T } from "../ui/index.ts";
import { columnWidth } from "./SheetViewer.tsx";

type Doc = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly blocks: ReadonlyArray<MarkedToken>; readonly cut: boolean };

const openLink = (href: string) => {
  if (/^(https?|mailto):/i.test(href)) void Linking.openURL(href).catch(() => undefined);
};

/** Tokens with a React key each: where they start in the source, unique among their siblings. */
const placed = <Item extends { readonly raw: string }>(tokens: ReadonlyArray<Item>): ReadonlyArray<{ readonly node: Item; readonly key: string; readonly at: number }> => {
  let offset = 0;
  return tokens.map((node, at) => {
    const key = String(offset);
    offset += node.raw.length;
    return { node, key, at };
  });
};

/** Inline Markdown as nested text, so bold, code and links flow inside one paragraph. */
const inline = (tokens: ReadonlyArray<Token> | undefined): ReactNode =>
  placed(tokens ?? []).map(({ node: token, key }) => {
    const node = token as MarkedToken;
    switch (node.type) {
      case "text":
        return node.tokens === undefined ? unescape(node.text) : <Text key={key}>{inline(node.tokens)}</Text>;
      case "escape":
        return node.text;
      case "strong":
        return (
          <Text key={key} style={styles.strong}>
            {inline(node.tokens)}
          </Text>
        );
      case "em":
        return (
          <Text key={key} style={styles.em}>
            {inline(node.tokens)}
          </Text>
        );
      case "del":
        return (
          <Text key={key} style={styles.del}>
            {inline(node.tokens)}
          </Text>
        );
      case "codespan":
        return (
          <Text key={key} style={styles.codespan}>
            {node.text}
          </Text>
        );
      case "link":
        return (
          <Text key={key} style={styles.link} onPress={() => openLink(node.href)} accessibilityRole="link">
            {inline(node.tokens)}
          </Text>
        );
      case "image":
        return (
          <Text key={key} style={styles.quiet}>
            {node.text === "" ? "Image" : node.text}
          </Text>
        );
      case "br":
        return "\n";
      case "html":
        return (
          <Text key={key} style={styles.quiet}>
            {node.text}
          </Text>
        );
      default:
        return null;
    }
  });

function Table({ table }: { readonly table: Tokens.Table }) {
  const columns = table.header.map((cell, id) => ({ id, width: columnWidth(Math.max(cell.text.length, ...table.rows.map((row) => row[id]?.text.length ?? 0))) }));
  const row = (cells: ReadonlyArray<Tokens.TableCell>, head: boolean, key: string) => (
    <View key={key} style={styles.tableRow}>
      {columns.map((column) => (
        <T key={column.id} v={head ? "strong" : "body"} color={head ? color.ink : color.ink2} style={[styles.tableCell, { width: column.width, textAlign: cells[column.id]?.align ?? "left" }]}>
          {inline(cells[column.id]?.tokens)}
        </T>
      ))}
    </View>
  );
  // A row's raw text isn't kept, so each is keyed by its place: rows never move.
  const rows = table.rows.map((cells, id) => ({ id: String(id), cells }));
  return (
    <ScrollView horizontal nestedScrollEnabled showsHorizontalScrollIndicator={false}>
      <View>
        {row(table.header, true, "head")}
        {rows.map(({ id, cells }) => row(cells, false, id))}
      </View>
    </ScrollView>
  );
}

/** One block: a heading, paragraph, list, quote, code, table or rule. Lists and quotes hold more blocks. */
function Block({ token }: { readonly token: MarkedToken }) {
  switch (token.type) {
    case "heading":
      return (
        <T accessibilityRole="header" selectable v="heading" style={HEADINGS[Math.min(token.depth, HEADINGS.length) - 1]}>
          {inline(token.tokens)}
        </T>
      );
    case "paragraph":
    case "text":
      return (
        <T color={color.ink2} selectable style={styles.paragraph}>
          {"tokens" in token && token.tokens !== undefined ? inline(token.tokens) : unescape(token.text)}
        </T>
      );
    case "code":
      return (
        <ScrollView horizontal nestedScrollEnabled showsHorizontalScrollIndicator={false} style={styles.code} contentContainerStyle={styles.codeInner}>
          <T v="mono" color={color.ink2} selectable>
            {token.text}
          </T>
        </ScrollView>
      );
    case "blockquote":
      return (
        <View style={styles.quote}>
          <Blocks tokens={token.tokens} />
        </View>
      );
    case "list":
      return (
        <View style={styles.list}>
          {placed(token.items).map(({ node: item, key, at }) => (
            <View key={key} style={styles.item}>
              <T color={item.task ? color.ink2 : color.mute} style={styles.marker}>
                {item.task ? (item.checked === true ? "☑" : "☐") : token.ordered ? `${String((token.start === "" ? 1 : token.start) + at)}.` : "•"}
              </T>
              <View style={styles.itemBody}>
                <Blocks tokens={item.tokens} />
              </View>
            </View>
          ))}
        </View>
      );
    case "table":
      return <Table table={token} />;
    case "hr":
      return <View style={styles.rule} />;
    case "html":
      return (
        <T v="mono" selectable>
          {token.text.trim()}
        </T>
      );
    default:
      return null;
  }
}

function Blocks({ tokens }: { readonly tokens: ReadonlyArray<Token> }) {
  return (
    <View style={styles.blocks}>
      {placed(tokens).map(({ node, key }) => (node.type === "space" || node.type === "checkbox" ? null : <Block key={key} token={node as MarkedToken} />))}
    </View>
  );
}

const keyOf = (_block: MarkedToken, index: number): string => String(index);

/** A Markdown or MDX file, rendered: headings, lists, tables, code and links. Each top-level block is a list item, so a long file scrolls smoothly. */
export function MarkdownViewer({ file, bottom }: { readonly file: File; readonly bottom: number }) {
  const [doc, setDoc] = useState<Doc>({ _tag: "loading" });

  useEffect(() => {
    let gone = false;
    readText(file)
      .then(({ text, cut }) => !gone && setDoc({ _tag: "loaded", blocks: markdownBlocks(text, /\.mdx$/i.test(file.name)), cut }))
      .catch((cause: unknown) => !gone && setDoc({ _tag: "failed", message: cause instanceof Error ? cause.message : "This file didn't open" }));
    return () => {
      gone = true;
    };
  }, [file]);

  if (doc._tag === "loading") return <Empty title="Opening" />;
  if (doc._tag === "failed") return <Empty title="Can't show this file" detail={doc.message} />;
  if (doc.blocks.length === 0) return <Empty title="Empty" />;
  return (
    <LegendList
      data={doc.blocks}
      keyExtractor={keyOf}
      renderItem={({ item }) => (
        <View style={styles.block}>
          <Block token={item} />
        </View>
      )}
      estimatedItemSize={60}
      ListHeaderComponent={doc.cut ? <T v="small" style={styles.block}>Showing the first 256 KB</T> : null}
      ListFooterComponent={<View style={{ height: bottom }} />}
      style={styles.fill}
    />
  );
}

/** h1 to h4; deeper headings look like h4. */
const HEADINGS = [
  { fontSize: 26, lineHeight: 32 },
  { fontSize: 21, lineHeight: 27 },
  { fontSize: 17, lineHeight: 23 },
  { fontSize: 15, lineHeight: 21 },
] as const;

const styles = StyleSheet.create({
  fill: { flex: 1 },
  block: { paddingHorizontal: 20, paddingBottom: 14 },
  blocks: { gap: 8 },
  paragraph: { fontSize: 15, lineHeight: 23 },
  strong: { fontFamily: font.sansSemibold, color: color.ink },
  em: { fontStyle: "italic" },
  del: { textDecorationLine: "line-through" },
  codespan: { fontFamily: font.mono, fontSize: 13, color: color.ink, backgroundColor: color.s3 },
  link: { color: color.yellow },
  quiet: { color: color.mute },
  code: { backgroundColor: color.s2, borderRadius: 10 },
  codeInner: { padding: 12 },
  quote: { borderLeftWidth: 2, borderColor: color.line2, paddingLeft: 12 },
  list: { gap: 6 },
  item: { flexDirection: "row", gap: 8 },
  marker: { minWidth: 16, fontSize: 15, lineHeight: 23 },
  itemBody: { flex: 1 },
  tableRow: { flexDirection: "row", borderBottomWidth: StyleSheet.hairlineWidth, borderColor: color.line2 },
  tableCell: { paddingHorizontal: 8, paddingVertical: 6 },
  rule: { height: StyleSheet.hairlineWidth, backgroundColor: color.line2, marginVertical: 6 },
});
