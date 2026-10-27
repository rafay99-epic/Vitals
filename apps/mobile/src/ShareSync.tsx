import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { stayConnected } from "@vitals/app/connection/session.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useEffect, useState } from "react";
import { AppState } from "react-native";

import { holdSharing, releaseSharing, sharesInBackground } from "../modules/vitals-share/index.ts";
import { PhoneShare, phoneRoots, sharedFolders, shareFiles, sharePhotos } from "./lib/share.ts";

export function ShareSync() {
  const remote = useRemote();
  const on = useStore(shareFiles);
  const photos = useStore(sharePhotos);
  const folders = useStore(sharedFolders);
  const [active, setActive] = useState(AppState.currentState === "active");
  const serving = on && (active || sharesInBackground);

  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => setActive(state === "active"));
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    if (on && active) void holdSharing().then((held) => held && stayConnected.set(true));
  }, [on, active]);

  useEffect(() => {
    if (!on) return;
    return () => {
      releaseSharing();
      stayConnected.set(false);
    };
  }, [on]);

  useEffect(() => {
    if (!serving) return;
    const share = new PhoneShare(remote);
    share.start(phoneRoots(photos, folders));
    return () => share.stopServing();
  }, [remote, serving, photos, folders]);

  return null;
}
