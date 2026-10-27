import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge, clipMeta, clipTitle } from "@vitals/app/features/clips/format.ts";
import type { SavedFile, SentDrop } from "@vitals/app/state/drops.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import { formatBytes } from "@vitals/shared";
import { useFocusEffect, useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import type { Clip, DeviceId, FsDevice, FsEntry, FsRecentKind, FsRoot } from "@vitals/contracts";
import { useCallback, useEffect, useState } from "react";
import { FlatList, Image, SectionList, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { DropCards } from "../DropTransfers.tsx";
import { EntryRow, isGallery, KIND_TITLE, PhotoTile } from "../FsRows.tsx";
import type { Batch } from "../lib/clips.ts";
import { copyToPhone, pickFiles, pickPhotos } from "../lib/clips.ts";
import { BLOCK_NOTE, type FileKind, fileKind, KIND_NAME, keepsGoing, pickFolder, savedTo, useFilesBlock } from "../lib/drops.ts";
import { useAccess } from "../lib/remote.ts";
import type { ControlStackParams } from "../navigation.ts";
import { clipSheet, sendSheet } from "../sheets/ClipSheets.tsx";
import { macFileSheet, type OnPhone } from "../sheets/MacFileSheet.tsx";
import { ClipRow } from "./ClipboardScreen.tsx";
import { receivedSheet, sentSheet } from "../sheets/FileSheets.tsx";
import { BackBar, Chip, color, Empty, Group, Icon, type IconName, Label, Note, Row, SearchField, sheet, T, Tap, Tile, TileGrid, Title, toast, Toggle, space, useDockSpace } from "../ui/index.ts";

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
  photos: "image",
  storage: "android",
  folder: "folder",
};

type Places = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly roots: ReadonlyArray<FsRoot> };

type Recents = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly entries: ReadonlyArray<FsEntry>; readonly more: boolean };

const KINDS: ReadonlyArray<FsRecentKind> = ["screenshots", "photos", "downloads", "documents"];
const STRIP = 12;
const ROWS = 3;
const TILE = 92;

const LOADING: Readonly<Record<FsRecentKind, Recents>> = { photos: { _tag: "loading" }, screenshots: { _tag: "loading" }, downloads: { _tag: "loading" }, documents: { _tag: "loading" } };

/** A section title with "See all" on the right. */
function Head({ title, onSeeAll }: { readonly title: string; readonly onSeeAll?: (() => void) | undefined }) {
  return (
    <View style={styles.head}>
      <T v="label">{title}</T>
      {onSeeAll === undefined ? null : (
        <Tap onPress={onSeeAll} accessibilityRole="button" accessibilityLabel={`See all ${title}`} hitSlop={10}>
          <T v="label" color={color.yellow}>
            See all
          </T>
        </Tap>
      )}
    </View>
  );
}

function Quiet({ children }: { readonly children: string }) {
  return (
    <T v="small" style={styles.quiet}>
      {children}
    </T>
  );
}

/** The newest few of one kind: a strip of pictures, or a few rows of files. */
function RecentSection({ kind, recents, phone, now, onSeeAll }: { readonly kind: FsRecentKind; readonly recents: Recents; readonly phone: OnPhone | null; readonly now: number; readonly onSeeAll: () => void }) {
  const open = (entry: FsEntry) => sheet.open(macFileSheet(entry, phone));
  const loaded = recents._tag === "loaded" && recents.entries.length > 0 ? recents.entries : null;
  return (
    <View>
      <Head title={KIND_TITLE[kind]} onSeeAll={loaded === null ? undefined : onSeeAll} />
      {recents._tag === "loading" ? (
        <Quiet>Loading</Quiet>
      ) : recents._tag === "failed" ? (
        <Quiet>{recents.message}</Quiet>
      ) : loaded === null ? (
        <Quiet>Nothing yet</Quiet>
      ) : isGallery(kind) ? (
        <FlatList
          horizontal
          data={loaded.slice(0, STRIP)}
          keyExtractor={(entry) => entry.path}
          renderItem={({ item }) => <PhotoTile entry={item} device={phone?.device} size={TILE} onPress={open} />}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.strip}
        />
      ) : (
        loaded.slice(0, ROWS).map((entry) => <EntryRow key={entry.path} entry={entry} device={phone?.device} now={now} onPress={open} />)
      )}
    </View>
  );
}

const copyable = (clip: Clip): boolean => clip.kind === "text" || clip.kind === "link" || clip.kind === "image";

/** The latest three things this device copied. Copy puts one on this phone's clipboard, pictures too. */
function ClipSection({ device, now }: { readonly device: FsDevice | null; readonly now: number }) {
  const remote = useRemote();
  const access = useAccess();
  const navigation = useNavigation<NativeStackNavigationProp<ControlStackParams>>();
  const clips = useStore(remote.clips.clips);
  const enabled = useStore(remote.clips.enabled);
  const supported = useStore(remote.clips.supported);
  const me = remote.credentials.deviceId;
  if (!access.clipboard || supported === false) return null;
  const from = device?.deviceId ?? null;
  const latest = clips.filter((clip) => clip.deviceId === from).slice(0, ROWS);
  const copy = (clip: Clip) =>
    void copyToPhone(remote, clip).then((copied) => copied && toast.show(clip.kind === "image" ? "Image copied. Paste it anywhere." : "Copied to this phone"));
  return (
    <View>
      <Head title="Clipboard" onSeeAll={latest.length === 0 ? undefined : () => navigation.push("Clipboard")} />
      {enabled === false ? (
        <Quiet>Clipboard history is off on the Mac.</Quiet>
      ) : latest.length === 0 ? (
        <Quiet>Nothing yet</Quiet>
      ) : (
        latest.map((clip) => (
          <ClipRow
            key={clip.id}
            clip={clip}
            meta={clipMeta(clip, me, now)}
            onPress={() => sheet.open(clipSheet(clip))}
            action={
              copyable(clip) ? (
                <Tap onPress={() => copy(clip)} accessibilityRole="button" accessibilityLabel={`Copy ${clipTitle(clip)}`} hitSlop={8} style={styles.copy}>
                  <T v="medium" color={color.yellow}>
                    Copy
                  </T>
                </Tap>
              ) : undefined
            }
          />
        ))
      )}
    </View>
  );
}

/** "All files": the device's shared folders, and search on the Mac. */
function AllFiles({ device }: { readonly device: FsDevice | null }) {
  const remote = useRemote();
  const navigation = useNavigation<NativeStackNavigationProp<ControlStackParams>>();
  const [places, setPlaces] = useState<Places>({ _tag: "loading" });
  const [query, setQuery] = useState("");
  const [found, setFound] = useState<ReadonlyArray<FsEntry> | null>(null);
  const id = device?.deviceId;

  useEffect(() => {
    let cancelled = false;
    void remote.files.roots(id).then((outcome) => {
      if (!cancelled) setPlaces(outcome.ok ? { _tag: "loaded", roots: outcome.value.roots } : { _tag: "failed", message: outcome.message });
    });
    return () => {
      cancelled = true;
    };
  }, [remote, id]);

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
  const searching = device === null && query.trim().length >= 2;
  const openEntry = (entry: FsEntry) =>
    entry.kind === "folder" || entry.kind === "link" ? navigation.push("Folder", { path: entry.path, title: entry.name }) : sheet.open(macFileSheet(entry));
  const openRoot = (root: FsRoot) => navigation.push("Folder", { path: root.path, title: root.label, ...(device === null ? {} : { device: device.deviceId, deviceName: device.name }) });

  return (
    <View>
      <Head title="All files" />
      {device === null ? <SearchField placeholder="Search your Mac" value={query} onChangeText={type} accessibilityLabel="Search your Mac" /> : null}
      {searching ? (
        found === null ? (
          <Quiet>Searching</Quiet>
        ) : found.length === 0 ? (
          <Quiet>Nothing found</Quiet>
        ) : (
          found.map((entry) => <PlaceRow key={entry.path} icon={entry.kind === "folder" ? "folder" : "file"} title={entry.name} detail={folderOf(entry.path)} onPress={() => openEntry(entry)} />)
        )
      ) : places._tag === "loading" ? (
        <Quiet>Loading</Quiet>
      ) : places._tag === "failed" ? (
        <Quiet>{places.message}</Quiet>
      ) : (
        places.roots.map((root) => <PlaceRow key={root.path} icon={PLACE_ICON[root.place]} title={root.label} onPress={() => openRoot(root)} />)
      )}
    </View>
  );
}

/** Every kind on one device, newest first. Reloads each time Files comes back into view. */
function DeviceRows({ device }: { readonly device: FsDevice | null }) {
  const remote = useRemote();
  const navigation = useNavigation<NativeStackNavigationProp<ControlStackParams>>();
  const now = useNow(60_000);
  const [recents, setRecents] = useState<Readonly<Record<FsRecentKind, Recents>>>(LOADING);
  const id = device?.deviceId;
  const phone = device === null ? null : { device: device.deviceId, name: device.name };

  useFocusEffect(
    useCallback(() => {
      let cancelled = false;
      for (const kind of KINDS) {
        void remote.files.recent(kind, 0, isGallery(kind) ? STRIP : ROWS, id).then((outcome) => {
          if (cancelled) return;
          setRecents((current) => ({ ...current, [kind]: outcome.ok ? { _tag: "loaded", entries: outcome.value.entries, more: outcome.value.more } : { _tag: "failed", message: outcome.message } }));
          if (outcome.ok) remote.files.want(outcome.value.entries, id);
        });
      }
      return () => {
        cancelled = true;
      };
    }, [remote, id]),
  );

  const seeAll = (kind: FsRecentKind) => navigation.push("Recent", { kind, ...(device === null ? {} : { device: device.deviceId, deviceName: device.name }) });
  const failures = KINDS.map((kind) => recents[kind]).filter((item) => item._tag === "failed");
  const shared = failures.length === KINDS.length && failures.every((item) => item.message === failures[0]?.message) ? failures[0] : undefined;
  const section = (kind: FsRecentKind) => <RecentSection key={kind} kind={kind} recents={recents[kind]} phone={phone} now={now} onSeeAll={() => seeAll(kind)} />;

  return (
    <View>
      {shared === undefined ? (
        <>
          {section("screenshots")}
          {section("photos")}
          <ClipSection device={device} now={now} />
          {section("downloads")}
          {section("documents")}
        </>
      ) : (
        <>
          <Empty title={device === null ? "Can't see your Mac's recent files" : `Can't see ${device.name}'s recent files`} detail={shared.message} />
          <ClipSection device={device} now={now} />
        </>
      )}
      <AllFiles device={device} />
    </View>
  );
}

/** The device page: a switcher (Mac, then each phone that shares), then that device's rows. */
function DeviceHub() {
  const remote = useRemote();
  const [devices, setDevices] = useState<ReadonlyArray<FsDevice>>([]);
  const [picked, setPicked] = useState<DeviceId | null>(null);
  const state = useStore(remote.connection.state);
  const ready = state._tag === "Ready";
  const me = remote.credentials.deviceId;

  useFocusEffect(
    useCallback(() => {
      if (!ready) return;
      void remote.files.devices().then((outcome) => outcome.ok && setDevices(outcome.value.devices.filter((device) => device.deviceId !== me)));
    }, [remote, ready, me]),
  );

  const device = devices.find((item) => item.deviceId === picked) ?? null;

  return (
    <View>
      {devices.length > 0 ? (
        <FlatList
          horizontal
          data={devices}
          keyExtractor={(item) => item.deviceId}
          ListHeaderComponent={<Chip label="Mac" on={device === null} onPress={() => setPicked(null)} />}
          renderItem={({ item }) => <Chip label={item.name} on={device?.deviceId === item.deviceId} onPress={() => setPicked(item.deviceId)} />}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.devices}
        />
      ) : null}
      {device !== null && !device.online ? (
        device.connected === true ? (
          <Empty title={`${device.name} isn't sharing its files`} detail="On it, turn on Let your Mac and other phones browse, in Settings › This phone." />
        ) : (
          <Empty title={`Open Vitals on ${device.name}`} detail={device.platform === "ios" ? "An iPhone shares only while Vitals is open on it." : "Then turn on Let your Mac and other phones browse, in Settings › This phone."} />
        )
      ) : (
        <DeviceRows key={device?.deviceId ?? "mac"} device={device} />
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
      {browsable ? <DeviceHub /> : null}
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
  devices: { gap: 8, paddingHorizontal: 16, paddingBottom: 10 },
  head: { flexDirection: "row", justifyContent: "space-between", paddingHorizontal: space.gutter, paddingTop: 14, paddingBottom: 8 },
  quiet: { paddingHorizontal: space.gutter, paddingBottom: 6 },
  strip: { gap: 8, paddingHorizontal: 16 },
  copy: { paddingHorizontal: 6, paddingVertical: 4 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 8 },
  rowText: { flex: 1 },
  icon: { width: 34, height: 34, borderRadius: 10 },
  iconTile: { backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  tag: { borderWidth: 1, borderColor: color.orange, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2 },
});
