import { stayConnected } from "@vitals/app/connection/session.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import type { ConnectionState } from "@vitals/client-runtime";
import { useEffect } from "react";
import { AppState } from "react-native";

import { describeLink, holdLink, linkHeld, releaseLink } from "../modules/vitals-share/index.ts";
import { useMac } from "./lib/remote.ts";
import { shareFiles } from "./lib/share.ts";

/** The notification's line for a connection state. Plain words, nothing the link can't back up. */
const lineOf = (state: ConnectionState, sharing: boolean): string => {
  switch (state._tag) {
    case "Ready":
      return `Connected over ${state.route === "lan" ? "Wi-Fi" : "Tailscale"}${sharing ? " · sharing files" : ""}`;
    case "Idle":
    case "Connecting":
      return "Connecting";
    case "Backoff":
      return "Reconnecting";
    case "Suspended":
      return "Paused";
    case "Revoked":
      return "Removed on the Mac";
    case "Incompatible":
      return "Update Vitals Remote to connect";
  }
};

/**
 * Keeps the link to the Mac alive while paired, even with the app closed (Android), behind one
 * ongoing notification. It starts each time the app opens; Disconnect in the notification stops it
 * until the next open. The Mac removing this phone stops it for good.
 */
export function LinkSync() {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const mac = useMac();
  const sharing = useStore(shareFiles);
  const ended = state._tag === "Revoked" || state._tag === "Incompatible";

  useEffect(() => {
    if (ended) return;
    if (AppState.currentState === "active") void holdLink();
    const subscription = AppState.addEventListener("change", (next) => {
      if (next === "active") void holdLink();
    });
    return () => {
      subscription.remove();
      releaseLink();
    };
  }, [ended]);

  // Held means stay connected. Let go with the app in the background (Disconnect) and the session pauses it.
  useEffect(() => linkHeld.subscribe(() => stayConnected.set(linkHeld.get())), []);

  useEffect(() => describeLink(mac?.name ?? "Your Mac", lineOf(state, sharing)), [mac?.name, state, sharing]);

  return null;
}
