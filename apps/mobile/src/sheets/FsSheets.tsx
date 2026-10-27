import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { deviceInfo } from "@vitals/app/lib/device.ts";
import { type Destination, destinationsFor, type FsSource } from "@vitals/app/state/files.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import type { FsEntry } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { type ComponentType, useEffect, useRef } from "react";
import { Image, StyleSheet, View } from "react-native";

import { useThumb, whatOf, whereOf } from "../FsRows.tsx";
import { type Batch, pickFiles, pickPhotos } from "../lib/clips.ts";
import { BLOCK_NOTE, keepsGoing, macFolder, pickFolder, savedTo, sendDrop, sendToPhone, transferFiles, useFilesBlock } from "../lib/drops.ts";
import { useAccess } from "../lib/remote.ts";
import { openPreview } from "../navigation.ts";
import { ActionRow, BigButton, color, Icon, type IconName, sheet, SheetCancel, SheetHeader, SheetNote, T, Tap, toast } from "../ui/index.ts";

const folderOf = (path: string): string => path.split("/").slice(-3, -1).join(" › ");

/** One file: its thumbnail, Open (the preview here), Transfer, and Open on the Mac for Mac files. */
export const fileSheet = (entry: FsEntry, source: FsSource): ComponentType =>
  function FileSheet() {
    const remote = useRemote();
    const thumb = useThumb(entry.path, source.device);
    const size = entry.kind === "file" ? formatBytes(entry.size) : "package";
    const openOnMac = () => {
      sheet.close();
      void remote.files.open(entry.path).then((outcome) => toast.show(outcome.ok ? "Opened on your Mac" : outcome.message, { tone: outcome.ok ? "ok" : "bad" }));
    };
    return (
      <>
        {thumb === null ? null : <Image source={{ uri: thumb }} style={styles.preview} resizeMode="contain" accessibilityIgnoresInvertColors />}
        <SheetHeader title={entry.name} detail={[size, `on ${whereOf(source)}`, folderOf(entry.path)].filter((part) => part !== "").join(" · ")} />
        <BigButton label="Transfer" onPress={() => sheet.open(transferSheet([entry], source))} />
        <ActionRow
          icon="eye"
          label="Open"
          detail="See it here without transferring"
          onPress={() => {
            sheet.close();
            openPreview({ entry, source, parent: entry.path.split("/").at(-2) ?? whereOf(source) });
          }}
        />
        {source.device === null ? <ActionRow icon="mac" label="Open on the Mac" onPress={openOnMac} /> : null}
        <SheetCancel label="Close" />
      </>
    );
  };

const LOOK: Readonly<Record<Destination["_tag"], IconName>> = { Here: "phone", Mac: "mac", Phone: "phone" };

const nameOf = (to: Destination): string => (to._tag === "Here" ? "This phone" : to._tag === "Mac" ? "Mac" : to.device.name);

const detailOf = (to: Destination): string => {
  if (to._tag === "Here") return `${deviceInfo().name} · into ${savedTo}`;
  if (to._tag === "Mac") return `Into ${macFolder}`;
  const into = to.device.platform === "ios" ? "Files › Vitals" : "Downloads › Vitals";
  return (to.device.connected ?? to.device.online) ? `Into ${into}` : `Not connected now · into ${into}`;
};

function DestinationRow({ to, disabled = false, onPress }: { readonly to: Destination; readonly disabled?: boolean; readonly onPress: () => void }) {
  return (
    <Tap onPress={onPress} disabled={disabled} accessibilityRole="button" accessibilityLabel={`${nameOf(to)}, ${detailOf(to)}`} style={styles.dest}>
      <Icon name={LOOK[to._tag]} size={20} color={color.yellow} />
      <View style={styles.destText}>
        <T v="strong">{nameOf(to)}</T>
        <T v="small" numberOfLines={1}>
          {detailOf(to)}
        </T>
      </View>
      <T v="strong" color={color.yellow}>
        {to._tag === "Here" ? "Here" : "Send"}
      </T>
    </Tap>
  );
}

/** The other phones, refreshed when a sheet that lists them opens. */
const usePhones = () => {
  const remote = useRemote();
  useEffect(() => {
    void remote.files.devices();
  }, [remote]);
  return useStore(remote.files.phones);
};

/** Where picked files on the Mac or a phone can go. Never the device they're on; copy only. `onDone` runs once a transfer starts. */
export const transferSheet = (entries: ReadonlyArray<FsEntry>, source: FsSource, onDone?: () => void): ComponentType =>
  function TransferSheet() {
    const remote = useRemote();
    const phones = usePhones();
    const what = whatOf(entries);
    const go = (to: Destination) => {
      sheet.close();
      onDone?.();
      void transferFiles(
        remote,
        source,
        entries.map((entry) => entry.path),
        what,
        to,
      );
    };
    return (
      <>
        <SheetHeader title={`Transfer ${what}`} detail={`From ${whereOf(source)}. It keeps its copy.`} />
        {destinationsFor(source.device, remote.credentials.deviceId, phones).map((to) => (
          <DestinationRow key={to._tag === "Phone" ? to.device.deviceId : to._tag} to={to} onPress={() => go(to)} />
        ))}
        <SheetCancel />
      </>
    );
  };

/**
 * Sends files picked on this phone to the Mac (Downloads › Vitals) or, through the Mac, to another phone.
 * Also opened by sharing files into Vitals. `onDone` runs once, after the send starts or the sheet closes.
 */
export const sendToSheet = (batch: Batch, onDone?: () => void): ComponentType =>
  function SendToSheet() {
    const remote = useRemote();
    const access = useAccess();
    const block = useFilesBlock();
    const phones = usePhones();
    const me = remote.credentials.deviceId;
    const done = useRef(false);
    useEffect(
      () => () => {
        if (!done.current) onDone?.();
      },
      [],
    );
    const go = (to: Destination) => {
      done.current = true;
      sheet.close();
      void (to._tag === "Phone" ? sendToPhone(remote, batch, to.device) : sendDrop(remote, batch))
        .then((sent) => sent && toast.show(`Sending ${batch.label} to ${to._tag === "Phone" ? to.device.name : "your Mac"}`))
        .finally(() => onDone?.());
    };
    const blocked = block !== null || !access.operate;
    return (
      <>
        <SheetHeader title={`Send ${batch.label}`} detail={[batch.bytes > 0 ? formatBytes(batch.bytes) : null, "From this phone"].filter((part) => part !== null).join(" · ")} />
        {destinationsFor(me, me, phones).map((to) => (
          <DestinationRow key={to._tag === "Phone" ? to.device.deviceId : to._tag} to={to} disabled={blocked} onPress={() => go(to)} />
        ))}
        <SheetNote>{block !== null ? BLOCK_NOTE[block] : access.operate ? keepsGoing : "This phone can only watch. Turn on control for it in Vitals on the Mac."}</SheetNote>
        <SheetCancel />
      </>
    );
  };

const pickThen = (picker: () => Promise<Batch | null>) => () => {
  sheet.close();
  void picker().then((batch) => batch !== null && sheet.open(sendToSheet(batch)));
};

/** "Send from this phone": pick photos, files or a folder, then where they go. */
export function SendFromPhoneSheet() {
  return (
    <>
      <SheetHeader title="Send from this phone" detail="Pick what to send, then where it goes." />
      <ActionRow icon="image" label="Pick photos" onPress={pickThen(pickPhotos)} />
      <ActionRow icon="file" label="Pick files" onPress={pickThen(pickFiles)} />
      <ActionRow icon="folder" label="Pick a folder" detail="Keeps its folders" onPress={pickThen(pickFolder)} />
      <SheetCancel />
    </>
  );
}

const styles = StyleSheet.create({
  preview: { height: 220, marginHorizontal: 16, marginBottom: 12, borderRadius: 16, backgroundColor: color.bg },
  dest: { flexDirection: "row", alignItems: "center", gap: 13, marginHorizontal: 16, marginBottom: 8, backgroundColor: color.s3, borderRadius: 16, paddingHorizontal: 14, paddingVertical: 12 },
  destText: { flex: 1, gap: 2 },
});
