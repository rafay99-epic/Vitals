import { useRemote } from "@vitals/app/connection/useRemote.ts";
import type { SavedFile } from "@vitals/app/state/drops.ts";
import type { DeviceId, FsEntry } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import type { ComponentType } from "react";
import { Image, StyleSheet } from "react-native";

import { useThumb } from "../FsRows.tsx";
import { copySavedImage, fileKind, getFromMac, savedTo, shareSaved } from "../lib/drops.ts";
import { ActionRow, sheet, SheetCancel, SheetHeader, toast } from "../ui/index.ts";

/** Where a file lives when it isn't on the Mac. */
export interface OnPhone {
  readonly device: DeviceId;
  readonly name: string;
}

/**
 * One file on the Mac or on another phone. Get saves a copy here; the original stays put.
 * Mac files can also go straight to this clipboard (pictures), to Share, or open on the Mac.
 */
export const macFileSheet = (entry: FsEntry, phone: OnPhone | null = null): ComponentType =>
  function MacFileSheet() {
    const remote = useRemote();
    const thumb = useThumb(entry.path, phone?.device);
    const size = entry.kind === "file" ? formatBytes(entry.size) : "package";
    const picture = entry.kind === "file" && fileKind(entry.name, null) === "image";

    const get = () => {
      sheet.close();
      if (phone !== null) {
        void remote.files.pull(phone.device, [entry.path]).then((outcome) =>
          toast.show(outcome.ok ? `${phone.name} is sending ${entry.name} through your Mac` : outcome.message, { tone: outcome.ok ? "ok" : "bad" }),
        );
        return;
      }
      void getFromMac(remote, [entry.path]).then((started) => started && toast.show(`Getting ${entry.name} from your Mac`));
    };

    const getThen = (use: (file: SavedFile) => Promise<void>) => () => {
      sheet.close();
      void getFromMac(remote, [entry.path], (files) => {
        const file = files[0];
        if (file !== undefined) void use(file);
      }).then((started) => started && toast.show(`Getting ${entry.name} from your Mac`));
    };

    const openOnMac = () => {
      sheet.close();
      void remote.files.open(entry.path).then((outcome) => toast.show(outcome.ok ? "Opened on your Mac" : outcome.message, { tone: outcome.ok ? "ok" : "bad" }));
    };

    return (
      <>
        <SheetHeader title={entry.name} detail={`${size} · on ${phone === null ? "your Mac" : phone.name}`} />
        {thumb === null ? null : <Image source={{ uri: thumb }} style={styles.preview} resizeMode="contain" accessibilityIgnoresInvertColors />}
        <ActionRow icon="down" label="Get it" detail={`${size} · to ${savedTo}`} onPress={get} />
        {phone === null && picture ? <ActionRow icon="copy" label="Copy image" detail="Paste it in any app" onPress={getThen(copySavedImage)} /> : null}
        {phone === null ? <ActionRow icon="share" label="Share" detail="to WhatsApp, Drive, any app" onPress={getThen(shareSaved)} /> : null}
        {phone === null ? <ActionRow icon="mac" label="Open on the Mac" onPress={openOnMac} /> : null}
        <SheetCancel />
      </>
    );
  };

const styles = StyleSheet.create({
  preview: { height: 180, marginHorizontal: 16, marginBottom: 12, borderRadius: 16 },
});
