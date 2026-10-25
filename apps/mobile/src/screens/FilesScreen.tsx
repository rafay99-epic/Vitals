import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge } from "@vitals/app/features/clips/format.ts";
import type { SavedFile, SentDrop } from "@vitals/app/state/drops.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import { formatBytes } from "@vitals/shared";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import type { FsEntry, FsRoot } from "@vitals/contracts";
import { useEffect, useState } from "react";
import { Image, SectionList, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { DropCards } from "../DropTransfers.tsx";
import type { Batch } from "../lib/clips.ts";
import { pickFiles, pickPhotos } from "../lib/clips.ts";
import { BLOCK_NOTE, type FileKind, fileKind, KIND_NAME, keepsGoing, pickFolder, savedTo, useFilesBlock } from "../lib/drops.ts";
import { useAccess } from "../lib/remote.ts";
import type { ControlStackParams } from "../navigation.ts";
import { sendSheet } from "../sheets/ClipSheets.tsx";
import { macFileSheet } from "../sheets/MacFileSheet.tsx";
import { receivedSheet, sentSheet } from "../sheets/FileSheets.tsx";
import { BackBar, color, Empty, Group, Icon, type IconName, Label, Note, Row, SearchField, sheet, T, Tap, Tile, TileGrid, Title, toast, Toggle, useDockSpace } from "../ui/index.ts";

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

const PLACE_ICON: Readonly<Record<FsRoot["place"], IconName>> = {
  home: "home",
  desktop: "screen",
  documents: "file",
  downloads: "down",
  movies: "video",
  music: "sound",
  pictures: "image",
  disk: "mac",
  volume: "files",
};

type Places = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly roots: ReadonlyArray<FsRoot> };

function MacPlaces() {
  const remote = useRemote();
  const navigation = useNavigation<NativeStackNavigationProp<ControlStackParams>>();
  const [places, setPlaces] = useState<Places>({ _tag: "loading" });
  const [query, setQuery] = useState("");
  const [found, setFound] = useState<ReadonlyArray<FsEntry> | null>(null);
  const state = useStore(remote.connection.state);
  const ready = state._tag === "Ready";

  useEffect(() => {
    if (!ready) return;
    let cancelled = false;
    void remote.files.roots().then((outcome) => {
      if (!cancelled) setPlaces(outcome.ok ? { _tag: "loaded", roots: outcome.value.roots } : { _tag: "failed", message: outcome.message });
    });
    return () => {
      cancelled = true;
    };
  }, [remote, ready]);

  useEffect(() => {
    const text = query.trim();
    if (text.length < 2) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      void remote.files.search(text).then((outcome) => {
        if (cancelled) return;
        setFound(outcome.ok ? outcome.value.entries : []);
        if (outcome.ok) remote.files.want(outcome.value.entries);
      });
    }, SEARCH_DELAY_MS);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [remote, query]);

  const type = (text: string) => {
    setQuery(text);
    if (text.trim().length < 2) setFound(null);
  };
  const searching = query.trim().length >= 2;
  const openEntry = (entry: FsEntry) =>
    entry.kind === "folder" || entry.kind === "link" ? navigation.push("Folder", { path: entry.path, title: entry.name }) : sheet.open(macFileSheet(entry, false));

  return (
    <View>
      <Label>On your Mac</Label>
      <SearchField placeholder="Search your Mac" value={query} onChangeText={type} accessibilityLabel="Search your Mac" />
      {searching ? (
        found === null ? (
          <Empty title="Searching" />
        ) : found.length === 0 ? (
          <Empty title="Nothing found" />
        ) : (
          found.map((entry) => <PlaceRow key={entry.path} icon={entry.kind === "folder" ? "folder" : "file"} title={entry.name} detail={folderOf(entry.path)} onPress={() => openEntry(entry)} />)
        )
      ) : places._tag === "loading" ? (
        <Empty title="Loading" />
      ) : places._tag === "failed" ? (
        <Empty title="Can't see your Mac's folders" detail={places.message} />
      ) : (
        places.roots.map((root) => <PlaceRow key={root.path} icon={PLACE_ICON[root.place]} title={root.label} onPress={() => navigation.push("Folder", { path: root.path, title: root.label })} />)
      )}
    </View>
  );
}

const folderOf = (path: string): string => path.split("/").slice(-3, -1).join(" › ");

function PlaceRow({ icon, title, detail, onPress }: { readonly icon: IconName; readonly title: string; readonly detail?: string; readonly onPress: () => void }) {
  return (
    <Tap onPress={onPress} accessibilityRole="button" accessibilityLabel={title} scale={0.99} style={styles.row}>
      <View style={[styles.icon, styles.iconTile]}>
        <Icon name={icon} size={16} color={color.blue} />
      </View>
      <View style={styles.rowText}>
        <T v="medium" numberOfLines={1}>
          {title}
        </T>
        {detail === undefined ? null : (
          <T v="small" numberOfLines={1}>
            {detail}
          </T>
        )}
      </View>
      <Icon name="chevron" size={15} color={color.mute} />
    </Tap>
  );
}

const SEARCH_DELAY_MS = 250;

export function FilesScreen() {
  const remote = useRemote();
  const access = useAccess();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(30_000);
  const block = useFilesBlock();
  const received = useStore(remote.drops.received);
  const sent = useStore(remote.drops.sent);
  const autoAccept = useStore(remote.drops.autoAccept);
  const canSend = access.operate && block === null;
  const state = useStore(remote.connection.state);
  const browsable = access.browse && state._tag === "Ready" && state.hello.fs === true;
  const startWithoutAsking = (on: boolean) => {
    remote.drops.setAutoAccept(on);
    toast.show(on ? "Files from your Mac start right away" : "Vitals asks before each transfer");
  };

  const pick = (picker: () => Promise<Batch | null>) => void picker().then((batch) => batch !== null && sheet.open(sendSheet({ ...batch, to: "downloads" })));

  const sections: ReadonlyArray<Section> = [
    { key: "in", title: "From your Mac", data: received.map((file): Item => ({ _tag: "in", file })) },
    { key: "out", title: "Sent", data: sent.map((drop): Item => ({ _tag: "out", drop })) },
  ];

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <BackBar parent="Control" />
      <Title>Files.</Title>
      {browsable ? <MacPlaces /> : null}
      <Label>Send to your Mac</Label>
      <T v="mono" style={styles.where}>{`From your Mac → ${savedTo}`}</T>
      <TileGrid>
        <Tile icon="files" label="Files" disabled={!canSend} onPress={() => pick(pickFiles)} />
        <Tile icon="image" label="Photos" disabled={!canSend} onPress={() => pick(pickPhotos)} />
        <Tile icon="folder" label="Folder" disabled={!canSend} onPress={() => pick(pickFolder)} />
      </TileGrid>
      {block === null ? null : <Note>{BLOCK_NOTE[block]}</Note>}
      {block === null && !access.operate ? <Note>This phone can only watch. Turn on control for it in Vitals on the Mac.</Note> : null}
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
  where: { paddingHorizontal: 20, paddingBottom: 12 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 8 },
  rowText: { flex: 1 },
  icon: { width: 34, height: 34, borderRadius: 10 },
  iconTile: { backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  tag: { borderWidth: 1, borderColor: color.orange, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2 },
});
