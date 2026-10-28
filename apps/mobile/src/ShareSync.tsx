import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useEffect, useState } from "react";
import { AppState } from "react-native";

import { linkHeld } from "../modules/vitals-share/index.ts";
import { allFilesWanted, askFullStorage, PhoneShare, phoneRoots, sharedFolders, shareFiles, sharePhotos, useLimitedStorage } from "./lib/share.ts";
import { BigButton, sheet, SheetCancel, SheetHeader } from "./ui/index.ts";

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

  return null;
}
