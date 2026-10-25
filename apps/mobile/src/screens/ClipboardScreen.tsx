import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipMeta, clipTitle, isCommand, isSameDay } from "@vitals/app/features/clips/format.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { Clip, ClipKind } from "@vitals/contracts";
import * as Clipboard from "expo-clipboard";
import { type ReactNode, useState } from "react";
import { Image, ScrollView, SectionList, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { autoCopy, setAutoCopy } from "../lib/autoCopy.ts";
import { batchOf, imageUri, pastedImage, pickFiles, pickPhotos, sendBatch, textItem } from "../lib/clips.ts";
import { useAccess } from "../lib/remote.ts";
import { clipSheet, sendSheet } from "../sheets/ClipSheets.tsx";
import { TransferCard } from "../Transfers.tsx";
import {
  BackBar,
  BigButton,
  Chip,
  color,
  ComposeField,
  Empty,
  Group,
  Icon,
  type IconName,
  Label,
  Note,
  Row,
  sheet,
  T,
  Tap,
  Tile,
  TileGrid,
  TileSlot,
  Title,
  toast,
  Toggle,
  useDockSpace,
} from "../ui/index.ts";

const KIND_LOOK: Readonly<Record<ClipKind, { readonly icon: IconName; readonly tint: string }>> = {
  text: { icon: "text", tint: color.ink2 },
  link: { icon: "link", tint: color.blue },
  image: { icon: "image", tint: color.pink },
  file: { icon: "file", tint: color.orange },
  folder: { icon: "folder", tint: color.green },
};

type Filter = "all" | "pinned" | "text" | "link" | "image" | "file";

/** Files includes folders: both save the same way. */
const FILTERS: ReadonlyArray<{ readonly key: Filter; readonly label: string; readonly match: (clip: Clip) => boolean }> = [
  { key: "all", label: "All", match: () => true },
  { key: "pinned", label: "Pinned", match: (clip) => clip.pinned },
  { key: "text", label: "Text", match: (clip) => clip.kind === "text" },
  { key: "link", label: "Links", match: (clip) => clip.kind === "link" },
  { key: "image", label: "Images", match: (clip) => clip.kind === "image" },
  { key: "file", label: "Files", match: (clip) => clip.kind === "file" || clip.kind === "folder" },
];

/** The kind icon, or the image itself when there is a preview. */
function ClipIcon({ clip }: { readonly clip: Clip }) {
  const uri = clip.kind === "image" ? imageUri(clip) : null;
  if (uri !== null) return <Image source={{ uri }} style={styles.icon} accessibilityIgnoresInvertColors />;
  const look = KIND_LOOK[clip.kind];
  return (
    <View style={[styles.icon, styles.iconTile]}>
      <Icon name={look.icon} size={16} color={look.tint} />
    </View>
  );
}

/** One clip: icon, title (commands in mono), meta, a "sent" tag for phone-sent clips, and a pin mark. */
export function ClipRow({ clip, meta, onPress, action }: { readonly clip: Clip; readonly meta: string; readonly onPress: () => void; readonly action?: ReactNode }) {
  const title = clipTitle(clip);
  return (
    <Tap onPress={onPress} accessibilityRole="button" accessibilityLabel={`${title}, ${meta}`} scale={0.99} style={styles.row}>
      <ClipIcon clip={clip} />
      <View style={styles.rowText}>
        <T v={isCommand(clip) ? "monoStrong" : "medium"} numberOfLines={1}>
          {title}
        </T>
        <T v="small" numberOfLines={1}>
          {meta}
        </T>
      </View>
      {clip.deviceId === null ? null : (
        <View style={styles.tag}>
          <T v="tag">sent</T>
        </View>
      )}
      {clip.pinned ? <Icon name="pin" size={14} color={color.yellow} /> : null}
      {action}
    </Tap>
  );
}

/** iOS has Apple's paste button, which needs no "Allow Paste" prompt. Elsewhere the tile reads the clipboard on tap. */
function PasteTile({ disabled, onText, onImage }: { readonly disabled: boolean; readonly onText: (text: string) => void; readonly onImage: (dataUri: string) => void }) {
  if (Clipboard.isPasteButtonAvailable && !disabled) {
    return (
      <TileSlot>
        <Clipboard.ClipboardPasteButton
          style={styles.paste}
          backgroundColor={color.s2}
          foregroundColor={color.ink}
          cornerStyle="large"
          displayMode="iconAndLabel"
          acceptedContentTypes={["plain-text", "url", "image"]}
          imageOptions={{ format: "png" }}
          onPress={(data) => (data.type === "text" ? onText(data.text) : onImage(data.data))}
        />
      </TileSlot>
    );
  }
  const read = async () => {
    if (await Clipboard.hasImageAsync()) {
      const image = await Clipboard.getImageAsync({ format: "png" });
      if (image !== null) return onImage(image.data);
    }
    const text = await Clipboard.getStringAsync();
    if (text.trim() === "") return toast.show("Nothing to paste. Copy something first.");
    onText(text);
  };
  return <Tile icon="clipboard" label="Paste" disabled={disabled} onPress={() => void read()} />;
}

interface Section {
  readonly key: string;
  readonly title: string;
  readonly data: ReadonlyArray<Clip>;
}

const sectionsOf = (clips: ReadonlyArray<Clip>, now: number): ReadonlyArray<Section> => {
  const pinned = clips.filter((clip) => clip.pinned);
  const rest = clips.filter((clip) => !clip.pinned);
  return [
    { key: "pinned", title: "Pinned", data: pinned },
    { key: "today", title: "Today", data: rest.filter((clip) => isSameDay(clip.at, now)) },
    { key: "earlier", title: "Earlier", data: rest.filter((clip) => !isSameDay(clip.at, now)) },
  ].filter((section) => section.data.length > 0);
};

/** Older Macs only answer "what's on the clipboard now", as plain text. */
function OldMac() {
  const remote = useRemote();
  const [text, setText] = useState<string | null>(null);
  const read = () =>
    void remote.connection.call((client) => client["clipboard.get"]({})).then((result) => {
      if (result.ok) setText(result.value.text ?? "The Mac clipboard is empty.");
      else toast.show(result.error.message, { tone: "bad" });
    });
  return (
    <>
      <Empty title="History needs a newer Vitals on the Mac" detail="Update Vitals on the Mac to see what it copied and to send photos and files." />
      <BigButton ghost label="Get the Mac's clipboard" onPress={read} />
      {text === null ? null : (
        <T v="mono" color={color.ink} selectable style={styles.oldText}>
          {text}
        </T>
      )}
    </>
  );
}

const copyMacCopies = (on: boolean) => {
  setAutoCopy(on);
  toast.show(on ? "New Mac copies will land on this phone" : "Mac copies stay on the Mac");
};

/** Control > Clipboard: send to the Mac, browse what it copied, and auto-copy Mac copies here. */
export function ClipboardScreen() {
  const remote = useRemote();
  const access = useAccess();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const now = useNow(30_000);
  const clips = useStore(remote.clips.clips);
  const enabled = useStore(remote.clips.enabled);
  const keepDays = useStore(remote.clips.keepDays);
  const supported = useStore(remote.clips.supported);
  const copyHere = useStore(autoCopy);
  const [filter, setFilter] = useState<Filter>("all");
  const [draft, setDraft] = useState("");
  const me = remote.credentials.deviceId;
  const canSend = access.operate;
  const canFiles = canSend && supported !== false;
  const showHistory = access.clipboard && supported !== false && enabled === true;

  const sendText = (text: string) => void sendBatch(remote, batchOf([textItem(text)], "typed here"), "clipboard");
  const compose = () => {
    if (draft.trim() === "") return;
    sendText(draft);
    setDraft("");
  };
  const pick = (picker: typeof pickPhotos) => void picker().then((batch) => batch !== null && sheet.open(sendSheet(batch)));

  const match = FILTERS.find((item) => item.key === filter)?.match ?? (() => true);
  const sections = showHistory ? sectionsOf(clips.filter(match), now) : [];

  const history = (): ReactNode => {
    if (!access.clipboard) return <Note>Reading the Mac clipboard is off for this phone.</Note>;
    if (supported === false) return <OldMac />;
    if (enabled === null) return <Empty title="Reading the Mac." />;
    if (!enabled) return <Empty title="Clipboard history is off on the Mac." detail="Turn it on in Vitals on the Mac, under Remote." />;
    return (
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
        {FILTERS.map((item) => (
          <Chip key={item.key} label={item.label} count={clips.filter(item.match).length} on={filter === item.key} onPress={() => setFilter(item.key)} />
        ))}
      </ScrollView>
    );
  };

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <BackBar parent="Control" />
      <Title>Clipboard.</Title>
      <ComposeField value={draft} onChangeText={setDraft} onSend={compose} placeholder="Type something for the Mac" label="Text for the Mac" disabled={!canSend} />
      <TileGrid>
        <PasteTile disabled={!canSend} onText={sendText} onImage={(data) => void sendBatch(remote, batchOf([pastedImage(data)], "pasted"), "clipboard")} />
        <Tile icon="image" label="Photos" disabled={!canFiles} onPress={() => pick(pickPhotos)} />
        <Tile icon="file" label="Files" disabled={!canFiles} onPress={() => pick(pickFiles)} />
      </TileGrid>
      {canSend ? null : <Note>This phone can only watch. Turn on control for it in Vitals on the Mac.</Note>}
      <TransferCard />
      {history()}
    </View>
  );

  const footer = (
    <View>
      {access.clipboard && supported !== false ? (
        <>
          <Label>On this phone</Label>
          <Group>
            <Row first label="Copy Mac copies here" control={<Toggle value={copyHere} label="Copy Mac copies to this phone" onChange={copyMacCopies} />} />
          </Group>
          <Note>
            {keepDays === null
              ? "Only while Vitals is open. Pinned clips stay on the Mac until you unpin them."
              : `Only while Vitals is open. Your Mac keeps ${String(keepDays)} ${keepDays === 1 ? "day" : "days"} of history, and pinned clips stay until you unpin them.`}
          </Note>
        </>
      ) : null}
      <View style={{ height: bottom }} />
    </View>
  );

  return (
    <SectionList
      style={styles.list}
      sections={sections}
      keyExtractor={(clip) => clip.id}
      renderItem={({ item }) => <ClipRow clip={item} meta={clipMeta(item, me, now)} onPress={() => sheet.open(clipSheet(item))} />}
      renderSectionHeader={({ section }) => <Label right={String(section.data.length)}>{section.title}</Label>}
      ListHeaderComponent={header}
      ListEmptyComponent={showHistory ? <Empty title={clips.length === 0 ? "Nothing copied yet" : "Nothing here yet"} /> : undefined}
      ListFooterComponent={footer}
      stickySectionHeadersEnabled={false}
      keyboardShouldPersistTaps="handled"
      keyboardDismissMode="on-drag"
      initialNumToRender={14}
      maxToRenderPerBatch={12}
      windowSize={9}
    />
  );
}

const styles = StyleSheet.create({
  list: { flex: 1, backgroundColor: color.bg },
  chips: { gap: 7, paddingHorizontal: 16, paddingBottom: 10 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 8 },
  rowText: { flex: 1 },
  icon: { width: 34, height: 34, borderRadius: 10 },
  iconTile: { backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  tag: { borderWidth: 1, borderColor: color.line2, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2 },
  paste: { height: 72, width: "100%" },
  oldText: { paddingHorizontal: 20, paddingTop: 12, lineHeight: 20 },
});
