import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge } from "@vitals/app/features/clips/format.ts";
import { dropLabel, type SavedFile, type SentDrop } from "@vitals/app/state/drops.ts";
import type { Drop } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import type { ComponentType } from "react";
import { Image, Platform, StyleSheet, View } from "react-native";

import { canInstallApps, fileKind, installSaved, KIND_NAME, openSaved, saveSavedToPhotos, savedTo, shareSaved } from "../lib/drops.ts";
import { ActionRow, BigButton, color, sheet, SheetCancel, SheetHeader, T, toast } from "../ui/index.ts";

const after = (run: () => Promise<void>) => () => {
  sheet.close();
  void run();
};

export const askSheet = (drop: Drop): ComponentType =>
  function AskSheet() {
    const remote = useRemote();
    const names = drop.files
      .slice(0, 3)
      .map((file) => file.name)
      .join(", ");
    const more = drop.files.length > 3 ? ` and ${String(drop.files.length - 3)} more` : "";
    return (
      <>
        <SheetHeader title={`Your Mac wants to send ${dropLabel(drop)}`} detail={`${formatBytes(drop.bytes)} · ${names}${more}`} />
        <BigButton
          label="Accept"
          onPress={() => {
            sheet.close();
            void remote.drops.accept(drop.id);
          }}
        />
        <SheetCancel label="Not now" />
      </>
    );
  };

function AppWarning() {
  return (
    <View style={styles.warn}>
      <T v="strong" color={color.orange}>
        This is an app
      </T>
      <T v="small" color={color.ink2}>
        {canInstallApps ? "Only install apps you trust. It came from your Mac." : "This phone can't install it from Vitals. It's saved as a file."}
      </T>
    </View>
  );
}

export const receivedSheet = (file: SavedFile): ComponentType =>
  function ReceivedSheet() {
    const remote = useRemote();
    const kind = fileKind(file.name, file.mime);
    const media = kind === "image" || kind === "video";
    const remove = () => {
      sheet.close();
      toast.show("Removed from the list. The file stays saved.", { action: "Undo", onAction: remote.drops.forgetReceived(file.id) });
    };
    return (
      <>
        <SheetHeader title={file.name} detail={[KIND_NAME[kind], formatBytes(file.size), "from your Mac", clipAge(file.at, Date.now())].join(" · ")} />
        {kind === "image" && file.uri !== null ? <Image source={{ uri: file.uri }} resizeMode="contain" style={styles.preview} accessibilityIgnoresInvertColors /> : null}
        {kind === "apk" ? <AppWarning /> : null}
        {kind === "apk" && canInstallApps ? <ActionRow icon="android" label="Install" detail="Opens Android's installer" onPress={after(() => installSaved(file))} /> : null}
        {media ? <ActionRow icon="down" label="Save to Photos" onPress={after(() => saveSavedToPhotos(file))} /> : null}
        <ActionRow icon="files" label={Platform.OS === "ios" ? "Show in Files" : "Open"} detail={savedTo} onPress={after(() => openSaved(file))} />
        <ActionRow icon="share" label="Share" detail="to Drive, WhatsApp, any app" onPress={after(() => shareSaved(file))} />
        <ActionRow icon="trash" label="Remove from this list" detail="The file stays saved" onPress={remove} />
      </>
    );
  };

export const sentSheet = (drop: SentDrop): ComponentType =>
  function SentSheet() {
    const remote = useRemote();
    const remove = () => {
      sheet.close();
      toast.show("Removed from the list. It stays on your Mac.", { action: "Undo", onAction: remote.drops.forgetSent(drop.id) });
    };
    const what = drop.files === 1 ? KIND_NAME[fileKind(drop.label, drop.mime)] : `${String(drop.files)} files`;
    return (
      <>
        <SheetHeader title={drop.label} detail={[what, formatBytes(drop.bytes), "in Downloads › Vitals on your Mac", clipAge(drop.at, Date.now())].join(" · ")} />
        <ActionRow icon="trash" label="Remove from this list" detail="It stays on your Mac" onPress={remove} />
      </>
    );
  };

const styles = StyleSheet.create({
  preview: { height: 180, marginHorizontal: 16, marginBottom: 12, borderRadius: 14, backgroundColor: color.bg },
  warn: { marginHorizontal: 16, marginBottom: 12, borderWidth: 1, borderColor: color.orange, borderRadius: 14, paddingHorizontal: 14, paddingVertical: 11, gap: 2 },
});
