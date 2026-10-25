import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useEffect, useState } from "react";
import { AppState } from "react-native";

import { PhoneShare, shareFiles } from "./lib/share.ts";

export function ShareSync() {
  const remote = useRemote();
  const on = useStore(shareFiles);
  const [active, setActive] = useState(AppState.currentState === "active");

  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => setActive(state === "active"));
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    if (!on || !active) return;
    const share = new PhoneShare(remote);
    share.start();
    return () => share.stopServing();
  }, [remote, on, active]);

  return null;
}
