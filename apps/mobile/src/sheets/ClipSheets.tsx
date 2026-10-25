import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipMeta, clipSize, KIND_NAME } from "@vitals/app/features/clips/format.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { type Clip, type ClipDestination, DROP_LIMITS } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { type ComponentType, useEffect, useRef, useState } from "react";
import { Image, Linking, StyleSheet, View } from "react-native";

import { type Batch, copyToPhone, imageUri, isFile, saveToFolder, saveToPhotos, sendBatch, shareClip } from "../lib/clips.ts";
import { keepsGoing, macFolder, sendDrop, useFilesBlock } from "../lib/drops.ts";
import { send, useAccess } from "../lib/remote.ts";
import { ActionRow, BigButton, color, Icon, type IconName, Label, Segmented, type SegmentOption, sheet, SheetHeader, SheetNote, T, toast } from "../ui/index.ts";

const whoTitle = (clip: Clip, me: string): string => {
  if (clip.deviceId === null) return `${KIND_NAME[clip.kind]} from your Mac`;
  return clip.deviceId === me ? `${KIND_NAME[clip.kind]} sent from this phone` : `${KIND_NAME[clip.kind]} sent from ${clip.source ?? "another phone"}`;
};

/** Text and links show in a mono box; images show their preview. */
function ClipHead({ clip }: { readonly clip: Clip }) {
  const uri = imageUri(clip);
  if (clip.kind === "image" && uri !== null) return <Image source={{ uri }} resizeMode="contain" style={styles.preview} accessibilityIgnoresInvertColors />;
  if (clip.kind !== "text" && clip.kind !== "link") return null;
  return (
    <View style={styles.monobox}>
      <T v="mono" color={color.ink} selectable numberOfLines={12} style={styles.monoText}>
        {clip.truncated ? `${clip.text ?? ""}…` : (clip.text ?? "")}
      </T>
    </View>
  );
}

/** Runs a clip action after the sheet closes, and confirms it when it worked. */
const after = (run: () => Promise<boolean | void>, done?: string) => () => {
  sheet.close();
  void run().then((ok) => {
    if (ok !== false && done !== undefined) toast.show(done);
  });
};

interface ClipAction {
  readonly icon: IconName;
  readonly label: string;
  readonly detail?: string | undefined;
  readonly needsOperate?: boolean;
  readonly run: () => void;
}

/** Copy and open: text, links and images land on this phone; links open here or on the Mac. */
const takeActions = (remote: Remote, clip: Clip): ReadonlyArray<ClipAction> => {
  const image = clip.kind === "image";
  const copy: ReadonlyArray<ClipAction> =
    clip.kind === "text" || clip.kind === "link" || image
      ? [{ icon: "copy", label: image ? "Copy image" : "Copy to this phone", run: after(() => copyToPhone(remote, clip), image ? "Image copied to this phone" : "Copied to this phone") }]
      : [];
  const url = clip.kind === "link" ? clip.text : null;
  if (url === null) return copy;
  return [
    ...copy,
    { icon: "link", label: "Open on this phone", run: after(() => Linking.openURL(url)) },
    { icon: "mac", label: "Open on Mac", needsOperate: true, run: after(() => send(remote, { _tag: "OpenUrl", url }, "Opened on your Mac")) },
  ];
};

/** Save and share: images to Photos, files to a folder, folders as a zip. */
const keepActions = (remote: Remote, clip: Clip): ReadonlyArray<ClipAction> => {
  const size = clipSize(clip) ?? undefined;
  const share: ClipAction = { icon: "share", label: "Share", detail: "to Drive, WhatsApp, any app", run: after(() => shareClip(remote, clip)) };
  switch (clip.kind) {
    case "image":
      return [{ icon: "down", label: "Save to Photos", detail: size, run: after(() => saveToPhotos(remote, clip)) }, share];
    case "file":
      return [{ icon: "down", label: "Save to this phone", detail: size === undefined ? "pick a folder" : `${size} · pick a folder`, run: after(() => saveToFolder(remote, clip)) }, share];
    case "folder":
      return [{ icon: "down", label: "Save as zip", detail: size, run: after(() => saveToFolder(remote, clip)) }, share];
    default:
      return [];
  }
};

/** History: put a phone-sent clip back on the Mac clipboard, pin, remove (with Undo). */
const historyActions = (remote: Remote, clip: Clip): ReadonlyArray<ClipAction> => [
  ...(clip.deviceId === null
    ? []
    : [{ icon: "mac", label: "Put on the Mac clipboard again", needsOperate: true, run: after(async () => (await remote.clips.put([clip.id], "clipboard")) !== null, "On your Mac's clipboard") } satisfies ClipAction]),
  {
    icon: "pin",
    label: clip.pinned ? "Unpin" : "Pin",
    detail: clip.pinned ? "History cleanup can remove it again" : "Kept until you unpin it",
    run: after(() => remote.clips.pin(clip, !clip.pinned), clip.pinned ? "Unpinned" : "Pinned. History cleanup won't remove it."),
  },
  {
    icon: "trash",
    label: "Remove from history",
    detail: "Deletes it from the Mac's history too",
    run: () => {
      sheet.close();
      toast.show("Removed from history", { action: "Undo", onAction: remote.clips.remove(clip) });
    },
  },
];

/**
 * One sheet for every clip. Actions depend on the kind: copy what can be copied, open links,
 * save images to Photos, save files and folders (as a zip), share, pin and remove.
 */
export const clipSheet = (clip: Clip): ComponentType =>
  function ClipSheet() {
    const remote = useRemote();
    const access = useAccess();
    const me = remote.credentials.deviceId;
    const actions = [...takeActions(remote, clip), ...keepActions(remote, clip), ...historyActions(remote, clip)];
    return (
      <>
        <SheetHeader title={whoTitle(clip, me)} detail={clipMeta(clip, me, Date.now())} />
        <ClipHead clip={clip} />
        {actions.map((action) => (
          <ActionRow key={action.label} icon={action.icon} label={action.label} detail={action.detail} disabled={action.needsOperate === true && !access.operate} onPress={action.run} />
        ))}
      </>
    );
  };

const DESTINATIONS: ReadonlyArray<SegmentOption<ClipDestination>> = [
  { value: "clipboard", label: "Mac clipboard" },
  { value: "downloads", label: "Downloads" },
];

/** What is about to go: up to two image previews, a file line, or the text itself. */
function BatchPreview({ batch }: { readonly batch: Batch }) {
  const files = batch.items.filter(isFile);
  const images = files.filter((item) => item.kind === "image").slice(0, 2);
  if (images.length > 0 && images.length === Math.min(2, batch.items.length)) {
    return (
      <View style={styles.previews}>
        {images.map((item) => (
          <Image key={item.uri} source={{ uri: item.uri }} resizeMode="cover" style={styles.previewHalf} accessibilityIgnoresInvertColors />
        ))}
      </View>
    );
  }
  const first = batch.items[0];
  if (first !== undefined && !isFile(first)) {
    return (
      <View style={styles.monobox}>
        <T v="mono" color={color.ink} numberOfLines={8} style={styles.monoText}>
          {first.text}
        </T>
      </View>
    );
  }
  return (
    <View style={styles.fileLine}>
      <Icon name="file" size={18} color={color.orange} />
      <View style={styles.fileText}>
        <T v="strong" numberOfLines={1}>
          {batch.label}
        </T>
        {batch.bytes > 0 ? <T v="small">{formatBytes(batch.bytes)}</T> : null}
      </View>
    </View>
  );
}

/**
 * "Send to your Mac": a preview, where it goes, and one button. Opened by the Photos, Files and
 * Folder tiles and by sharing into Vitals. Files for Downloads go through Drop when the Mac and
 * this app support it; the Mac clipboard takes up to 50 MB. `onDone` runs once, after the send
 * ends or the sheet closes.
 */
export const sendSheet = (batch: Batch, onDone?: () => void): ComponentType =>
  function SendSheet() {
    const remote = useRemote();
    const access = useAccess();
    const state = useStore(remote.connection.state);
    const block = useFilesBlock();
    const fits = batch.bytes <= DROP_LIMITS.clipboardBytes;
    const [to, setTo] = useState<ClipDestination>(fits ? batch.to : "downloads");
    const sending = useRef(false);
    useEffect(
      () => () => {
        if (!sending.current) onDone?.();
      },
      [],
    );
    const drop = to === "downloads" && block === null && batch.items.length > 0 && batch.items.every(isFile);
    const go = () => {
      sending.current = true;
      sheet.close();
      void (drop ? sendDrop(remote, batch) : sendBatch(remote, batch, to)).finally(() => onDone?.());
    };
    const route = state._tag === "Ready" ? (state.route === "lan" ? "Over Wi-Fi now." : "Over Tailscale now.") : "Waiting for your Mac.";
    const foot = drop ? keepsGoing : `${route} If the connection drops, it picks up where it stopped.`;
    return (
      <>
        <SheetHeader title="Send to your Mac" detail={[batch.label, batch.bytes > 0 ? formatBytes(batch.bytes) : null, batch.from].filter((part) => part !== null).join(" · ")} />
        <BatchPreview batch={batch} />
        <Label>Put it on</Label>
        <Segmented options={DESTINATIONS} value={to} onChange={setTo} disabled={!access.operate || !fits} />
        {fits ? null : <SheetNote>{`Too big for the clipboard. It goes to ${macFolder} on your Mac.`}</SheetNote>}
        <BigButton label="Send to Mac" disabled={!access.operate} onPress={go} />
        <SheetNote>{access.operate ? foot : "This phone can only watch. Turn on control for it in Vitals on the Mac."}</SheetNote>
      </>
    );
  };

const styles = StyleSheet.create({
  monobox: { marginHorizontal: 16, marginBottom: 12, backgroundColor: color.bg, borderWidth: 1, borderColor: color.line2, borderRadius: 14, padding: 12 },
  monoText: { lineHeight: 18 },
  preview: { height: 180, marginHorizontal: 16, marginBottom: 12, borderRadius: 14, backgroundColor: color.bg },
  previews: { flexDirection: "row", gap: 8, marginHorizontal: 16, marginBottom: 12 },
  previewHalf: { flex: 1, height: 140, borderRadius: 14, backgroundColor: color.bg },
  fileLine: { flexDirection: "row", alignItems: "center", gap: 12, marginHorizontal: 16, marginBottom: 12, backgroundColor: color.s3, borderRadius: 14, padding: 14 },
  fileText: { flex: 1, gap: 2 },
});
