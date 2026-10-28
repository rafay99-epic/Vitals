import { useStore } from "@vitals/app/state/useStore.ts";
import Constants from "expo-constants";
import { useEffect, useState } from "react";
import { AppState } from "react-native";

import { nightlyState } from "./lib/nightly.ts";
import { installPlay, playState, skippedPlay, skipPlay, startPlay } from "./lib/play.ts";
import { playVersion, SETTINGS_WORD, sheetFor, type UpdateSheet, type UpdateView, updateView } from "./lib/updateModel.ts";
import { downloadUpdate, launchedNewUpdate, restartIntoUpdate, rolledBack, thisLaunch, updateState } from "./lib/updates.ts";
import { BigButton, sheet, SheetCancel, SheetHeader, toast } from "./ui/index.ts";

/** How long after the app comes to the front an update may still ask. Later than that it waits for the next open. */
const FRESH_MS = 20_000;

/** Sheets already shown this launch, by key. */
const shown = new Set<string>();

function UpdatedSheet() {
  return (
    <>
      <SheetHeader title={`Updated to ${Constants.expoConfig?.version ?? "the newest version"}`} detail={thisLaunch.notes === "" ? undefined : thisLaunch.notes} />
      <BigButton label="Done" onPress={sheet.close} />
    </>
  );
}

const run = (action: () => unknown) => () => {
  sheet.close();
  void action();
};

const playFailed = (started: boolean) => started || toast.show("Google Play did not open. Try again.", { tone: "bad" });

const sheetOf = (update: UpdateSheet) => {
  switch (update.kind) {
    case "ready":
      return function ReadySheet() {
        return (
          <>
            <SheetHeader title="Update ready" detail={`${update.notes === "" ? "" : `${update.notes} `}Vitals restarts in about a second. Your Mac isn't touched.`} />
            <BigButton label="Restart now" onPress={run(restartIntoUpdate)} />
            <SheetCancel label="Later" />
          </>
        );
      };
    case "found":
      return function FoundSheet() {
        return (
          <>
            <SheetHeader title="Update ready to download" detail={update.notes === "" ? "A newer Vitals Remote is out." : update.notes} />
            <BigButton label="Download" onPress={run(() => downloadUpdate(update.id, update.notes))} />
            <SheetCancel label="Later" />
          </>
        );
      };
    case "play-found":
      return function PlayFoundSheet() {
        return (
          <>
            <SheetHeader title="New version on Google Play" detail={`Vitals Remote ${playVersion(update.version)} downloads while you keep using the app.`} />
            <BigButton label="Update" onPress={run(() => startPlay().then(playFailed))} />
            <SheetCancel label="Later" onPress={run(() => skipPlay(update.version))} />
          </>
        );
      };
    case "play-ready":
      return function PlayReadySheet() {
        return (
          <>
            <SheetHeader title="Update downloaded" detail="Restart to install. Vitals reopens where you were." />
            <BigButton label="Restart to install" onPress={run(installPlay)} />
            <SheetCancel label="Later" />
          </>
        );
      };
  }
};

/** Where updates stand, for the Updates page, its Settings row and the dot on the Settings tab. A new Nightly build waits too. */
export const useUpdateStatus = (): { readonly view: UpdateView; readonly word: string; readonly waiting: boolean } => {
  const view = updateView(useStore(updateState), useStore(playState), rolledBack);
  const nightly = useStore(nightlyState)._tag === "Available";
  const { word, waiting } = SETTINGS_WORD[view.kind];
  return view.kind === "current" && nightly ? { view, word: "New build", waiting: true } : { view, word, waiting };
};

/** Tells the user about updates with a sheet: once after one installed, and when one waits as the app opens. */
export function UpdateSync() {
  const quick = useStore(updateState);
  const play = useStore(playState);
  const skipped = useStore(skippedPlay);
  const [openedAt, setOpenedAt] = useState(Date.now);

  useEffect(() => {
    void launchedNewUpdate().then((updated) => {
      if (!updated) return;
      shown.add("updated");
      sheet.open(UpdatedSheet);
    });
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") setOpenedAt(Date.now());
    });
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    if (sheet.showing()) return;
    const next = sheetFor({ quick, play, fresh: Date.now() - openedAt < FRESH_MS, shown, skippedPlay: skipped });
    if (next === null) return;
    shown.add(next.key);
    sheet.open(sheetOf(next));
  }, [quick, play, skipped, openedAt]);

  return null;
}
