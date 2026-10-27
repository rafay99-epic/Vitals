import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge } from "@vitals/app/features/clips/format.ts";
import type { SavedFile, SentDrop } from "@vitals/app/state/drops.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import { formatBytes } from "@vitals/shared";
import { Image, SectionList, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { DropCards } from "../DropTransfers.tsx";
import { type FileKind, fileKind, KIND_NAME, keepsGoing } from "../lib/drops.ts";
import { receivedSheet, sentSheet } from "../sheets/FileSheets.tsx";
import { BackBar, color, Empty, Group, Icon, type IconName, Label, Note, Row, sheet, T, Tap, Title, toast, Toggle, useDockSpace } from "../ui/index.ts";

const KIND_LOOK: Readonly<Record<FileKind, { readonly icon: IconName; readonly tint: string }>> = {
  apk: { icon: "android", tint: color.green },
  video: { icon: "video", tint: color.blue },
  image: { icon: "image", tint: color.pink },
  doc: { icon: "file", tint: color.orange },
};

type Item = { readonly _tag: "in"; readonly file: SavedFile } | { readonly _tag: "out"; readonly drop: SentDrop };

interface Section {
  readonly key: "in" | "out";
  readonly title: string;
  readonly data: ReadonlyArray<Item>;
}

function KindIcon({ kind, uri }: { readonly kind: FileKind; readonly uri: string | null }) {
  if (kind === "image" && uri !== null) return <Image source={{ uri }} style={styles.icon} accessibilityIgnoresInvertColors />;
  const look = KIND_LOOK[kind];
  return (
    <View style={[styles.icon, styles.iconTile]}>
      <Icon name={look.icon} size={16} color={look.tint} />
    </View>
  );
}

function FileRow({ item, now }: { readonly item: Item; readonly now: number }) {
  const kind = item._tag === "in" ? fileKind(item.file.name, item.file.mime) : item.drop.files > 1 ? "doc" : fileKind(item.drop.label, item.drop.mime);
  const title = item._tag === "in" ? item.file.name : item.drop.label;
  const what = item._tag === "out" && item.drop.files > 1 ? `${String(item.drop.files)} files` : KIND_NAME[kind];
  const bytes = item._tag === "in" ? item.file.size : item.drop.bytes;
  const at = item._tag === "in" ? item.file.at : item.drop.at;
  const meta = [what, formatBytes(bytes), clipAge(at, now)].join(" · ");
  const open = () => sheet.open(item._tag === "in" ? receivedSheet(item.file) : sentSheet(item.drop));
  return (
    <Tap onPress={open} accessibilityRole="button" accessibilityLabel={`${title}, ${meta}`} scale={0.99} style={styles.row}>
      <KindIcon kind={kind} uri={item._tag === "in" ? item.file.uri : null} />
      <View style={styles.rowText}>
        <T v="medium" numberOfLines={1}>
          {title}
        </T>
        <T v="small" numberOfLines={1}>
          {meta}
        </T>
      </View>
      {kind === "apk" ? (
        <View style={styles.tag}>
          <T v="tag" color={color.orange}>
            app
          </T>
        </View>
      ) : null}
    </Tap>
  );
}

/** Files under way, files received on this phone and files sent from it, plus whether Mac files start without asking. */
export function TransfersScreen() {
  const remote = useRemote();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(30_000);
  const received = useStore(remote.drops.received);
  const sent = useStore(remote.drops.sent);
  const autoAccept = useStore(remote.drops.autoAccept);
  const startWithoutAsking = (on: boolean) => {
    remote.drops.setAutoAccept(on);
    toast.show(on ? "Files from your Mac start right away" : "Vitals asks before each transfer");
  };

  const sections: ReadonlyArray<Section> = [
    { key: "in", title: "Received", data: received.map((file): Item => ({ _tag: "in", file })) },
    { key: "out", title: "Sent", data: sent.map((drop): Item => ({ _tag: "out", drop })) },
  ];

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <BackBar parent="Files" />
      <Title>Transfers.</Title>
      <DropCards />
    </View>
  );

  const footer = (
    <View>
      <Label>From your Mac</Label>
      <Group>
        <Row first label="Start without asking" control={<Toggle value={autoAccept} label="Start without asking" onChange={startWithoutAsking} />} />
      </Group>
      <Note>{keepsGoing}</Note>
      <View style={{ height: bottom }} />
    </View>
  );

  return (
    <SectionList
      style={styles.list}
      sections={sections}
      keyExtractor={(item) => (item._tag === "in" ? item.file.id : `sent-${item.drop.id}`)}
      renderItem={({ item }) => <FileRow item={item} now={now} />}
      renderSectionHeader={({ section }) => <Label right={String(section.data.length)}>{section.title}</Label>}
      renderSectionFooter={({ section }) =>
        section.data.length > 0 ? null : <Empty title={section.key === "in" ? "Nothing yet" : "Nothing sent yet"} detail={section.key === "in" ? "On the Mac, right-click a file › Send to Phone." : undefined} />
      }
      ListHeaderComponent={header}
      ListFooterComponent={footer}
      stickySectionHeadersEnabled={false}
      initialNumToRender={14}
      maxToRenderPerBatch={12}
      windowSize={9}
    />
  );
}

const styles = StyleSheet.create({
  list: { flex: 1, backgroundColor: color.bg },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 8 },
  rowText: { flex: 1 },
  icon: { width: 34, height: 34, borderRadius: 10 },
  iconTile: { backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  tag: { borderWidth: 1, borderColor: color.orange, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2 },
});
