import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useEffect, useState } from "react";
import { AppState } from "react-native";

import { linkHeld } from "../modules/vitals-share/index.ts";
import { allFilesWanted, askedUnrestricted, askFullStorage, askUnrestricted, PhoneShare, phoneRoots, sharedFolders, shareFiles, sharePhotos, shouldAskUnrestricted, useLimitedStorage } from "./lib/share.ts";
import { BigButton, sheet, SheetCancel, SheetHeader, toast } from "./ui/index.ts";

/** Asked again at most this often when other devices keep running into the missing access. */
const ASK_AGAIN_MS = 2 * 60_000;

/** When the All files access sheet last showed. 0 until it has this launch. */
let askedAt = 0;

function AllFilesSheet() {
  return (
    <>
      <SheetHeader title="Allow access to your files" detail="Your Mac and other phones can't open this phone's folders yet. Android needs one switch turned on for Vitals." />
      <BigButton
        label="Turn it on"
        onPress={() => {
          sheet.close();
          void askFullStorage();
        }}
      />
      <SheetCancel label="Not now" />
    </>
  );
}

function BatterySheet() {
  return (
    <>
      <SheetHeader title="Keep sharing with the screen off" detail="Android pauses Vitals to save battery, so your Mac and other phones can't reach this phone while it's locked. Let Vitals run in the background." />
      <BigButton
        label="Allow"
        onPress={() => {
          sheet.close();
          void askUnrestricted().then((opened) => opened || toast.show("Android didn't open it. Set Vitals' battery use to Unrestricted in Settings › Apps.", { tone: "bad" }));
        }}
      />
      <SheetCancel label="Not now" />
    </>
  );
}

export function ShareSync() {
  const remote = useRemote();
  const on = useStore(shareFiles);
  const photos = useStore(sharePhotos);
  const folders = useStore(sharedFolders);
  const wantedAt = useStore(allFilesWanted);
  const limited = useLimitedStorage();
  const [active, setActive] = useState(AppState.currentState === "active");
  const held = useStore(linkHeld);
  // Sharing rides on the link service: it keeps serving with the app closed for as long as that runs.
  const serving = on && (active || held);

  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => setActive(state === "active"));
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    if (!serving) return;
    const share = new PhoneShare(remote);
    share.start(phoneRoots(photos, folders, !limited), limited);
    return () => share.stopServing();
  }, [remote, serving, photos, folders, limited]);

  // Shared without All files access: asks once a launch, and again when another device was kept out.
  useEffect(() => {
    if (!on || !active || !limited || sheet.showing()) return;
    if (askedAt !== 0 && wantedAt <= askedAt + ASK_AGAIN_MS) return;
    askedAt = Date.now();
    sheet.open(AllFilesSheet);
  }, [on, active, limited, wantedAt]);

  // Once, with sharing on: explain Android's battery limits and offer its prompt. Waits for any other sheet
  // (All files access asks first) and tries again when it closes.
  useEffect(() => {
    if (!on || !active) return;
    let checking = false;
    let shown = false;
    const offer = () => {
      if (shown || checking || sheet.showing()) return;
      checking = true;
      void shouldAskUnrestricted().then((needed) => {
        checking = false;
        if (!needed || shown || sheet.showing()) return;
        shown = true;
        askedUnrestricted();
        sheet.open(BatterySheet);
      });
    };
    offer();
    return sheet.onChange(offer);
  }, [on, active]);

  return null;
}
