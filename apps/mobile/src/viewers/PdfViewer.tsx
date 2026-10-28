import { LegendList } from "@legendapp/list/react-native";
import { Image } from "expo-image";
import { memo, useEffect, useState } from "react";
import { PixelRatio, StyleSheet, useWindowDimensions, View } from "react-native";

import { nativeFiles } from "../../modules/vitals-share/index.ts";
import { color, Empty, T } from "../ui/index.ts";

const GAP = 8;
/** Pages are drawn at most this many pixels wide, whatever the screen. */
const MAX_PIXELS = 1600;

interface Page {
  readonly index: number;
  readonly aspect: number;
}

type Pages = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly pages: ReadonlyArray<Page> };

const keyOf = (page: Page): string => String(page.index);

/** One page, drawn natively when it first comes near the screen. */
const PdfPage = memo(function PdfPage({ path, page, width, pixels }: { readonly path: string; readonly page: Page; readonly width: number; readonly pixels: number }) {
  const [uri, setUri] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let gone = false;
    void nativeFiles
      ?.pdfPage?.(path, page.index, pixels)
      .then((drawn) => !gone && setUri(drawn))
      .catch(() => !gone && setFailed(true));
    return () => {
      gone = true;
    };
  }, [path, page.index, pixels]);
  return (
    <View style={[styles.page, { width, height: width * page.aspect }]} accessibilityLabel={`Page ${String(page.index + 1)}`}>
      {uri === null ? (
        <T v="mono" color={color.mute}>
          {failed ? `Page ${String(page.index + 1)} didn't draw` : String(page.index + 1)}
        </T>
      ) : (
        <Image source={uri} transition={null} style={StyleSheet.absoluteFill} accessibilityIgnoresInvertColors />
      )}
    </View>
  );
});

/** Every page of a PDF in a vertical list that only draws the pages near the screen. */
export function PdfViewer({ path, bottom }: { readonly path: string; readonly bottom: number }) {
  const { width: screen, height } = useWindowDimensions();
  const [pages, setPages] = useState<Pages>(() =>
    nativeFiles?.pdfPages === undefined ? { _tag: "failed", message: "Update Vitals on this phone to read PDFs here. Open with another app for now." } : { _tag: "loading" },
  );
  const width = screen - 16;
  const pixels = Math.min(MAX_PIXELS, PixelRatio.getPixelSizeForLayoutSize(width));

  useEffect(() => {
    const count = nativeFiles?.pdfPages;
    if (count === undefined) return;
    let gone = false;
    count(path)
      .then((aspects) => !gone && setPages({ _tag: "loaded", pages: aspects.map((aspect, index) => ({ index, aspect: aspect > 0 ? aspect : Math.SQRT2 })) }))
      .catch((cause: unknown) => !gone && setPages({ _tag: "failed", message: cause instanceof Error ? cause.message : "This PDF didn't open" }));
    return () => {
      gone = true;
      void nativeFiles?.pdfClose?.();
    };
  }, [path]);

  if (pages._tag === "loading") return <Empty title="Opening" />;
  if (pages._tag === "failed") return <Empty title="Can't show this PDF" detail={pages.message} />;
  return (
    <LegendList
      data={pages.pages}
      keyExtractor={keyOf}
      getFixedItemSize={(page) => width * page.aspect + GAP}
      renderItem={({ item }) => <PdfPage path={path} page={item} width={width} pixels={pixels} />}
      drawDistance={height}
      ListFooterComponent={<View style={{ height: bottom }} />}
      style={styles.list}
    />
  );
}

const styles = StyleSheet.create({
  list: { flex: 1 },
  page: { alignSelf: "center", marginBottom: GAP, backgroundColor: color.s2, alignItems: "center", justifyContent: "center", overflow: "hidden" },
});
