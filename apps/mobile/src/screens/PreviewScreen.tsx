import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import type { FsSource } from "@vitals/app/state/files.ts";
import { type DeviceId, type FsEntry, FS_LIMITS } from "@vitals/contracts";
import { formatAmount } from "@vitals/app/features/clips/format.ts";
import { formatBytes } from "@vitals/shared";
import { File } from "expo-file-system";
import { Image } from "expo-image";
import { useEffect, useMemo, useRef, useState } from "react";
import { FlatList, type LayoutChangeEvent, type NativeScrollEvent, type NativeSyntheticEvent, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { lookOf, useThumb, whereOf } from "../FsRows.tsx";
import { cachedPreview, fetchPreview, openWith, previewKind, TOO_BIG } from "../lib/preview.ts";
import type { ControlStackParams } from "../navigation.ts";
import { transferSheet } from "../sheets/FsSheets.tsx";
import { BackBar, Bar, BigButton, color, Empty, Icon, sheet, T, Tap } from "../ui/index.ts";
import { ImageViewer } from "../viewers/ImageViewer.tsx";
import { MarkdownViewer } from "../viewers/MarkdownViewer.tsx";
import { MediaViewer } from "../viewers/MediaViewer.tsx";
import { PdfViewer } from "../viewers/PdfViewer.tsx";
import { SheetViewer } from "../viewers/SheetViewer.tsx";
import { TextViewer } from "../viewers/TextViewer.tsx";
import { ZipViewer } from "../viewers/ZipViewer.tsx";

type Props = NativeStackScreenProps<ControlStackParams, "Preview">;

/** Where the file is: not fetched (kinds only another app opens), coming over in chunks, here, or failed. */
type Copy =
  | { readonly _tag: "waiting" }
  | { readonly _tag: "fetching"; readonly done: number; readonly total: number }
  | { readonly _tag: "ready"; readonly file: File }
  | { readonly _tag: "failed"; readonly message: string };

/** Where a file starts out: already here, not needed yet, or to fetch. */
const copyOf = (entry: FsEntry, source: FsSource, local: string | undefined): Copy => {
  const here = local === undefined ? cachedPreview(entry, source) : new File(local);
  if (here !== null) return { _tag: "ready", file: here };
  return previewKind(entry.name) === "other" ? { _tag: "waiting" } : { _tag: "fetching", done: 0, total: entry.size };
};

/** `file:///a%20b` to `/a b`, for native code that wants a path. */
const pathOf = (uri: string): string => decodeURIComponent(uri.replace(/^file:\/\//, ""));

/** What a viewer-less file shows: its icon, name and size, and the ways to open it elsewhere. */
function FileCard({ entry, onOpenWith, onTransfer }: { readonly entry: FsEntry; readonly onOpenWith: () => void; readonly onTransfer: (() => void) | null }) {
  const look = lookOf(entry);
  return (
    <View style={styles.card}>
      <View style={styles.cardIcon}>
        <Icon name={look.icon} size={34} color={look.tint} />
      </View>
      <T v="heading" numberOfLines={2} style={styles.center}>
        {entry.name}
      </T>
      <T v="small">{formatBytes(entry.size)}</T>
      <View style={styles.cardButtons}>
        {onTransfer === null ? null : <BigButton label="Transfer" onPress={onTransfer} />}
        <BigButton label="Open with…" ghost onPress={onOpenWith} />
      </View>
    </View>
  );
}

/** Determinate progress while the file comes over: the thumbnail when there is one, a bar, and how much. */
function Fetching({ entry, device, done, total }: { readonly entry: FsEntry; readonly device: DeviceId | null; readonly done: number; readonly total: number }) {
  return (
    <View style={styles.card}>
      <FetchingThumb entry={entry} device={device} />
      <View style={styles.bar}>
        <Bar value={total === 0 ? 0 : done / total} />
      </View>
      <T v="mono">{formatAmount(done, total)}</T>
    </View>
  );
}

function FetchingThumb({ entry, device }: { readonly entry: FsEntry; readonly device: DeviceId | null }) {
  const thumb = useThumb(entry.path, device);
  if (thumb !== null) return <Image source={thumb} contentFit="contain" transition={null} style={styles.thumb} accessibilityIgnoresInvertColors />;
  const look = lookOf(entry);
  return (
    <View style={styles.cardIcon}>
      <Icon name={look.icon} size={34} color={look.tint} />
    </View>
  );
}

/** A file beside the one showing, while it's swiped in: the picture when it's here, else its thumbnail or icon. */
function Peek({ entry, source }: { readonly entry: FsEntry; readonly source: FsSource }) {
  const cached = previewKind(entry.name) === "image" ? cachedPreview(entry, source) : null;
  if (cached !== null) return <Image source={cached.uri} contentFit="contain" transition={null} style={styles.body} accessibilityIgnoresInvertColors />;
  return (
    <View style={styles.card}>
      <FetchingThumb entry={entry} device={source.device} />
    </View>
  );
}

const pathKey = (entry: FsEntry): string => entry.path;

/**
 * One file from the Mac or another phone, viewed right here: pictures, PDFs, Markdown, spreadsheets, text,
 * video and sound, and what's inside a zip. Swipe sideways for the files next to it. Only the file showing
 * comes over into this phone's cache; swiping away or leaving stops it.
 */
export function PreviewScreen({ navigation, route }: Props) {
  const remote = useRemote();
  const insets = useSafeAreaInsets();
  const { entry: opened, source, parent, local, siblings } = route.params;
  const files = useMemo(() => (siblings?.some((item) => item.path === opened.path) === true ? siblings : [opened]), [siblings, opened]);
  const [start] = useState(() => Math.max(0, files.findIndex((item) => item.path === opened.path)));
  const [at, setAt] = useState(start);
  const entry = files[at] ?? opened;
  const kind = previewKind(entry.name);
  const [copy, setCopy] = useState<Copy>(() => copyOf(entry, source, local));
  /** A zoomed picture pans instead of swiping. */
  const [zoomed, setZoomed] = useState(false);
  const [page, setPage] = useState({ width: 0, height: 0 });
  /** Open with was tapped before the file was here: hand it over once it is. */
  const openAfter = useRef(false);
  const fetching = copy._tag === "fetching";

  const measure = (event: LayoutChangeEvent) => setPage({ width: event.nativeEvent.layout.width, height: event.nativeEvent.layout.height });
  const settle = (event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const next = Math.round(event.nativeEvent.contentOffset.x / Math.max(1, page.width));
    const nextEntry = files[next];
    if (next === at || nextEntry === undefined) return;
    openAfter.current = false;
    setAt(next);
    setZoomed(false);
    setCopy(copyOf(nextEntry, source, undefined));
  };

  useEffect(() => {
    if (!fetching) return;
    let stopped = false;
    fetchPreview(remote, entry, source, (progress) => !stopped && setCopy({ _tag: "fetching", ...progress }), () => stopped)
      .then((file) => {
        if (stopped || file === null) return;
        setCopy({ _tag: "ready", file });
        if (openAfter.current) void openWith(file);
        openAfter.current = false;
      })
      .catch((cause: unknown) => !stopped && setCopy({ _tag: "failed", message: cause instanceof Error ? cause.message : "It didn't come over" }));
    return () => {
      stopped = true;
    };
  }, [fetching, remote, entry, source]);

  const transfer = local === undefined ? () => sheet.open(transferSheet([entry], source)) : null;
  const openElsewhere = () => {
    if (copy._tag === "ready") return void openWith(copy.file);
    openAfter.current = true;
    if (copy._tag !== "fetching") setCopy({ _tag: "fetching", done: 0, total: entry.size });
  };
  const openUnpacked = (inner: FsEntry, unpacked: File) => navigation.push("Preview", { entry: inner, source, parent: entry.name, local: unpacked.uri });

  const bottom = insets.bottom + 16;
  const body = (() => {
    if (copy._tag === "failed") {
      return (
        <View style={styles.card}>
          <Empty title="Can't preview this" detail={copy.message} />
          <View style={styles.cardButtons}>
            {copy.message === TOO_BIG || transfer === null ? null : <BigButton label="Try again" ghost onPress={() => setCopy({ _tag: "fetching", done: 0, total: entry.size })} />}
            {copy.message === TOO_BIG && transfer !== null ? <BigButton label="Transfer" onPress={transfer} /> : null}
          </View>
        </View>
      );
    }
    if (copy._tag === "fetching") return <Fetching entry={entry} device={source.device} done={copy.done} total={copy.total} />;
    if (copy._tag === "waiting" || kind === "other") return <FileCard entry={entry} onOpenWith={openElsewhere} onTransfer={transfer} />;
    switch (kind) {
      case "image":
        return <ImageViewer uri={copy.file.uri} onZoom={setZoomed} />;
      case "pdf":
        return <PdfViewer path={pathOf(copy.file.uri)} bottom={bottom} />;
      case "markdown":
        return <MarkdownViewer file={copy.file} bottom={bottom} />;
      case "sheet":
        return <SheetViewer file={copy.file} bottom={bottom} />;
      case "text":
        return <TextViewer file={copy.file} bottom={bottom} />;
      case "video":
      case "audio":
        return <MediaViewer uri={copy.file.uri} sound={kind === "audio"} />;
      case "zip":
        return <ZipViewer file={copy.file} bottom={bottom} onOpen={openUnpacked} />;
    }
  })();

  const from = local === undefined ? `on ${whereOf(source)}` : `in ${parent}`;
  return (
    <View style={styles.screen}>
      <View style={{ paddingTop: insets.top + 6 }}>
        <View style={styles.top}>
          <BackBar parent={parent} />
          <View style={styles.actions}>
            {kind === "other" || entry.size > FS_LIMITS.previewBytes ? null : (
              <Tap onPress={openElsewhere} accessibilityRole="button" hitSlop={10}>
                <T v="strong" color={color.yellow}>
                  Open with
                </T>
              </Tap>
            )}
            {transfer === null ? null : (
              <Tap onPress={transfer} accessibilityRole="button" hitSlop={10}>
                <T v="strong" color={color.yellow}>
                  Transfer
                </T>
              </Tap>
            )}
          </View>
        </View>
      </View>
      <View style={styles.body} onLayout={measure}>
        {page.width === 0 ? null : (
          <FlatList
            data={files}
            keyExtractor={pathKey}
            horizontal
            pagingEnabled
            scrollEnabled={files.length > 1 && !zoomed}
            showsHorizontalScrollIndicator={false}
            initialScrollIndex={start}
            getItemLayout={(_, index) => ({ length: page.width, offset: page.width * index, index })}
            initialNumToRender={1}
            maxToRenderPerBatch={2}
            windowSize={3}
            extraData={body}
            onMomentumScrollEnd={settle}
            renderItem={({ item, index }) => (
              // The name rides with its page, so it always swipes, even over a sheet that scrolls sideways.
              <View style={page}>
                <View style={styles.name}>
                  <T v="strong" numberOfLines={1}>
                    {item.name}
                  </T>
                  <T v="small" numberOfLines={1}>
                    {`${formatBytes(item.size)} · ${from}`}
                  </T>
                </View>
                <View style={styles.body}>{index === at ? body : <Peek entry={item} source={source} />}</View>
              </View>
            )}
          />
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: color.bg },
  top: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" },
  actions: { flexDirection: "row", gap: 18, paddingHorizontal: 20 },
  name: { paddingHorizontal: 20, paddingBottom: 10, gap: 2 },
  body: { flex: 1 },
  card: { flex: 1, alignItems: "center", justifyContent: "center", gap: 10, paddingHorizontal: 24 },
  cardIcon: { width: 84, height: 84, borderRadius: 22, backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  cardButtons: { alignSelf: "stretch", gap: 4, marginTop: 14 },
  center: { textAlign: "center" },
  thumb: { width: 160, height: 160, borderRadius: 12 },
  bar: { alignSelf: "stretch", marginTop: 6 },
});
