import { useFocusEffect, useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { type FsSource, mergeNewest, type RecentPage } from "@vitals/app/state/files.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { DeviceId, FsDevice, FsEntry, FsRecentKind, FsRoot } from "@vitals/contracts";
import { useCallback, useEffect, useState } from "react";
import { FlatList, StyleSheet, View } from "react-native";

import { DropCards } from "../DropTransfers.tsx";
import { EntryRow, isFolder, KindTile, PhotoTile, RootRow } from "../FsRows.tsx";
import { BLOCK_NOTE, useFilesBlock } from "../lib/drops.ts";
import { useAccess } from "../lib/remote.ts";
import { askFullStorage, shareFiles, shareThisPhone, useLimitedStorage } from "../lib/share.ts";
import type { ControlStackParams } from "../navigation.ts";
import { fileSheet, SendFromPhoneSheet } from "../sheets/FsSheets.tsx";
import { BackBar, color, Empty, Group, Page, Row, SearchField, Segmented, type SegmentOption, sheet, space, T, Tap, Title, Toggle } from "../ui/index.ts";

type Nav = NativeStackNavigationProp<ControlStackParams>;

type Loaded<A> = { readonly _tag: "loading" } | { readonly _tag: "failed"; readonly message: string } | { readonly _tag: "loaded"; readonly value: A };

const LOADING = { _tag: "loading" } as const;

const KINDS: ReadonlyArray<FsRecentKind> = ["screenshots", "photos", "downloads", "documents"];
const STRIP = 12;
/** Pictures fill the strip, so they load a strip's worth; files only need their newest one for the tile. */
const LIMIT: Readonly<Record<FsRecentKind, number>> = { screenshots: STRIP, photos: STRIP, downloads: 1, documents: 1 };
const THUMB = 100;
const SEARCH_DELAY_MS = 250;

const MAC: FsSource = { device: null, name: "Mac" };

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

const pageOf = (recents: Loaded<RecentPage>): RecentPage => (recents._tag === "loaded" ? recents.value : { entries: [], more: false });

/** The Mac's shared folders, or what a search of the Mac finds. */
function MacFolders({ roots, onRoot }: { readonly roots: Loaded<ReadonlyArray<FsRoot>>; readonly onRoot: (root: FsRoot) => void }) {
  const remote = useRemote();
  const navigation = useNavigation<Nav>();
  const now = useNow(60_000);
  const [query, setQuery] = useState("");
  const [found, setFound] = useState<ReadonlyArray<FsEntry> | null>(null);

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
  const open = (entry: FsEntry) => (isFolder(entry) ? navigation.push("Folder", { path: entry.path, source: MAC, trail: [entry.name] }) : sheet.open(fileSheet(entry, MAC)));
  const searching = query.trim().length >= 2;

  return (
    <>
      <SearchField placeholder="Search your Mac" value={query} onChangeText={type} accessibilityLabel="Search your Mac" />
      {searching ? (
        found === null ? (
          <Quiet>Searching</Quiet>
        ) : found.length === 0 ? (
          <Quiet>Nothing found</Quiet>
        ) : (
          found.map((entry) => <EntryRow key={entry.path} entry={entry} device={null} now={now} onPress={open} />)
        )
      ) : (
        <Roots roots={roots} onRoot={onRoot} />
      )}
    </>
  );
}

function Roots({ roots, onRoot }: { readonly roots: Loaded<ReadonlyArray<FsRoot>>; readonly onRoot: (root: FsRoot) => void }) {
  if (roots._tag === "loading") return <Quiet>Loading</Quiet>;
  if (roots._tag === "failed") return <Quiet>{roots.message}</Quiet>;
  if (roots.value.length === 0) return <Quiet>Nothing shared</Quiet>;
  return roots.value.map((root) => <RootRow key={root.path} root={root} onPress={onRoot} />);
}

/** One device's page: four kinds, the newest images, then its folders. Reloads each time Files comes back into view. */
function DeviceTab({ source }: { readonly source: FsSource }) {
  const remote = useRemote();
  const navigation = useNavigation<Nav>();
  const [recents, setRecents] = useState<Readonly<Record<FsRecentKind, Loaded<RecentPage>>>>({ screenshots: LOADING, photos: LOADING, downloads: LOADING, documents: LOADING });
  const [roots, setRoots] = useState<Loaded<ReadonlyArray<FsRoot>>>(LOADING);
  const device = source.device ?? undefined;

  useFocusEffect(
    useCallback(() => {
      let cancelled = false;
      for (const kind of KINDS) {
        void remote.files.recent(kind, 0, LIMIT[kind], device).then((outcome) => {
          if (cancelled) return;
          setRecents((current) => ({ ...current, [kind]: outcome.ok ? { _tag: "loaded", value: outcome.value } : { _tag: "failed", message: outcome.message } }));
          if (outcome.ok) remote.files.want(outcome.value.entries, device);
        });
      }
      void remote.files.roots(device).then((outcome) => {
        if (!cancelled) setRoots(outcome.ok ? { _tag: "loaded", value: outcome.value.roots } : { _tag: "failed", message: outcome.message });
      });
      return () => {
        cancelled = true;
      };
    }, [remote, device]),
  );

  const openRoot = (root: FsRoot) => navigation.push("Folder", { path: root.path, source, trail: [root.label] });

  return (
    <View>
      <Recents source={source} recents={recents} />
      <Head title="Folders" />
      {source.device === null ? <MacFolders roots={roots} onRoot={openRoot} /> : <Roots roots={roots} onRoot={openRoot} />}
    </View>
  );
}

const lineOf = (recent: Loaded<RecentPage>): string | null => (recent._tag === "loading" ? "Loading" : recent._tag === "failed" ? "Can't see them" : null);

/** The four kind tiles and the newest images, or why the device's recent files can't be seen. */
function Recents({ source, recents }: { readonly source: FsSource; readonly recents: Readonly<Record<FsRecentKind, Loaded<RecentPage>>> }) {
  const navigation = useNavigation<Nav>();
  const now = useNow(60_000);
  const failures = KINDS.map((kind) => recents[kind]).filter((item) => item._tag === "failed");
  const shared = failures.length === KINDS.length && failures.every((item) => item.message === failures[0]?.message) ? failures[0] : undefined;
  if (shared !== undefined) return <Empty title={`Can't see ${source.device === null ? "your Mac" : source.name}'s recent files`} detail={shared.message} />;
  const pictures = recents.screenshots._tag === "loading" && recents.photos._tag === "loading" ? null : mergeNewest([pageOf(recents.screenshots), pageOf(recents.photos)]).entries.slice(0, STRIP);
  const openFile = (entry: FsEntry) => sheet.open(fileSheet(entry, source));
  return (
    <>
      <View style={styles.tiles}>
        {KINDS.map((kind) => (
          <KindTile
            key={kind}
            kind={kind}
            newest={pageOf(recents[kind]).entries[0] ?? null}
            line={lineOf(recents[kind])}
            device={source.device}
            now={now}
            onPress={() => navigation.push("Recent", { kind, source })}
          />
        ))}
      </View>
      <Head title="Newest images" onSeeAll={pictures === null || pictures.length === 0 ? undefined : () => navigation.push("Recent", { kind: "images", source })} />
      {pictures === null ? (
        <Quiet>Loading</Quiet>
      ) : pictures.length === 0 ? (
        <Quiet>Nothing yet</Quiet>
      ) : (
        <FlatList
          horizontal
          data={pictures}
          keyExtractor={(entry) => entry.path}
          renderItem={({ item }) => <PhotoTile entry={item} device={source.device} size={THUMB} onPress={openFile} />}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.strip}
        />
      )}
    </>
  );
}

/** Why a tab has nothing to show, or null when it can show its files. `macFs` is null until the Mac connects. */
const blockedTab = (phone: FsDevice | null, browse: boolean, macFs: boolean | null): { readonly title: string; readonly detail?: string } | null => {
  if (phone === null) {
    if (!browse) return { title: "This phone can't browse your Mac", detail: "Allow it in Vitals on the Mac, under Remote." };
    if (macFs === null) return { title: "Waiting for your Mac" };
    return macFs ? null : { title: "Update Vitals on your Mac to browse its files" };
  }
  if (phone.online) return null;
  if (phone.connected === true) return { title: `${phone.name} isn't sharing its files`, detail: "On it, open Files and turn on This phone is shared." };
  return { title: `Open Vitals on ${phone.name}`, detail: phone.platform === "ios" ? "An iPhone shares only while Vitals is open on it." : "Then turn on This phone is shared, in Files." };
};

/** This phone's own sharing switch, and sending from it. */
function ThisPhone() {
  const access = useAccess();
  const sharing = useStore(shareFiles);
  const limited = useLimitedStorage();
  const block = useFilesBlock();
  return (
    <Group>
      <Row
        first
        label={sharing ? "This phone is shared" : "This phone isn't shared"}
        detail={sharing ? undefined : "Turn it on so your Mac and other phones can see its files."}
        control={<Toggle value={sharing} label="Share this phone" onChange={shareThisPhone} />}
      />
      {sharing && limited ? <Row label="All files on this phone" detail="Only Downloads › Vitals is shared now" value="Off" onPress={() => void askFullStorage()} /> : null}
      <Row
        label="Send from this phone"
        detail={block !== null ? BLOCK_NOTE[block] : access.operate ? undefined : "This phone can only watch. Turn on control for it in Vitals on the Mac."}
        onPress={block === null && access.operate ? () => sheet.open(SendFromPhoneSheet) : undefined}
      />
    </Group>
  );
}

/** Files: this phone's sharing on top, then a tab per other device (the Mac, then each phone), then Transfers. */
export function FilesScreen() {
  const remote = useRemote();
  const access = useAccess();
  const navigation = useNavigation<Nav>();
  const state = useStore(remote.connection.state);
  const phones = useStore(remote.files.phones);
  const received = useStore(remote.drops.received);
  const sent = useStore(remote.drops.sent);
  const [picked, setPicked] = useState<DeviceId | "mac">("mac");
  const ready = state._tag === "Ready";
  const me = remote.credentials.deviceId;

  useFocusEffect(
    useCallback(() => {
      if (ready && access.browse) void remote.files.devices();
    }, [remote, ready, access.browse]),
  );

  const others = phones.filter((device) => device.deviceId !== me);
  const phone = others.find((device) => device.deviceId === picked) ?? null;
  const tabs: ReadonlyArray<SegmentOption<DeviceId | "mac">> = [{ value: "mac", label: "Mac" }, ...others.map((device) => ({ value: device.deviceId, label: device.name }))];
  const blocked = blockedTab(phone, access.browse, ready ? state.hello.fs === true : null);
  const source: FsSource = phone === null ? MAC : { device: phone.deviceId, name: phone.name };

  return (
    <Page>
      <BackBar parent="Control" />
      <Title>Files.</Title>
      <ThisPhone />
      <DropCards />
      <Segmented options={tabs} value={phone?.deviceId ?? "mac"} onChange={setPicked} />
      {blocked === null ? <DeviceTab key={source.device ?? "mac"} source={source} /> : <Empty title={blocked.title} detail={blocked.detail} />}
      <View style={styles.transfers}>
        <Group>
          <Row first label="Transfers" detail={`${String(received.length)} received · ${String(sent.length)} sent`} onPress={() => navigation.navigate("Transfers")} />
        </Group>
      </View>
    </Page>
  );
}

const styles = StyleSheet.create({
  head: { flexDirection: "row", justifyContent: "space-between", paddingHorizontal: space.gutter, paddingTop: 18, paddingBottom: 8 },
  quiet: { paddingHorizontal: space.gutter, paddingBottom: 6 },
  tiles: { flexDirection: "row", flexWrap: "wrap", gap: 9, paddingHorizontal: space.edge },
  strip: { gap: 8, paddingHorizontal: space.edge },
  transfers: { paddingTop: 18 },
});
