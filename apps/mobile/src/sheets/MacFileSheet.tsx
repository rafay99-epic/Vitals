import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import type { FsEntry } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import type { ComponentType } from "react";
import { Image, StyleSheet } from "react-native";

import { savedTo } from "../lib/drops.ts";
import { ActionRow, Hold, sheet, SheetCancel, SheetHeader, toast } from "../ui/index.ts";

export const macFileSheet = (entry: FsEntry, canChange: boolean): ComponentType =>
  function MacFileSheet() {
    const remote = useRemote();
    const thumb = useStore(remote.files.thumbs).get(entry.path) ?? null;
    const size = entry.kind === "file" ? formatBytes(entry.size) : "package";

    const get = () => {
      sheet.close();
      void remote.drops.pull([entry.path]).then((drop) => {
        if (drop !== null) toast.show(`Getting ${entry.name} from your Mac`);
      });
    };

    const openOnMac = () => {
      sheet.close();
      void remote.files.open(entry.path).then((outcome) => toast.show(outcome.ok ? "Opened on your Mac" : outcome.message, { tone: outcome.ok ? "ok" : "bad" }));
    };

    const trash = () => {
      sheet.close();
      void remote.files.trash([entry.path]).then((outcome) =>
        toast.show(outcome.ok ? `${entry.name} is in the Trash on your Mac` : outcome.message, { tone: outcome.ok ? "ok" : "bad" }),
      );
    };

    return (
      <>
        <SheetHeader title={entry.name} detail={`${size} · on your Mac`} />
        {thumb === null ? null : <Image source={{ uri: thumb }} style={styles.preview} resizeMode="contain" accessibilityIgnoresInvertColors />}
        <ActionRow icon="down" label="Get it" detail={`${size} · to ${savedTo}`} onPress={get} />
        <ActionRow icon="mac" label="Open on the Mac" onPress={openOnMac} />
        {canChange ? <Hold label="Hold to move to the Mac's Trash" onCommit={trash} small /> : null}
        <SheetCancel />
      </>
    );
  };

const styles = StyleSheet.create({
  preview: { height: 180, marginHorizontal: 16, marginBottom: 12, borderRadius: 16 },
});
