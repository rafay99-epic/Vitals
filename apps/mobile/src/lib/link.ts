import { sessions, stayConnected } from "@vitals/app/connection/session.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import type { ConnectionState } from "@vitals/client-runtime";
import { AppState } from "react-native";

import { describeLink, holdLink, linkHeld, releaseLink } from "../../modules/vitals-share/index.ts";
import { hasFullStorage, PhoneShare, phoneRoots, sharedFolders, shareFiles, sharePhotos } from "./share.ts";

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

const ended = (state: ConnectionState): boolean => state._tag === "Revoked" || state._tag === "Incompatible";

/** Follows one paired Mac: holds the link, keeps its notification current, serves this phone's files. Returns a stop. */
const follow = (remote: Remote): (() => void) => {
  let name: string | null = null;
  let active = AppState.currentState === "active";
  let share: PhoneShare | null = null;
  let served = "";

  // Sharing serves while the app is open, and with it closed for as long as the link runs.
  const serve = () => {
    const on = shareFiles.get() && (active || linkHeld.get());
    const limited = !hasFullStorage();
    const key = on ? JSON.stringify([sharePhotos.get(), sharedFolders.get(), limited]) : "";
    if (key === served) return;
    served = key;
    share?.stopServing();
    share = null;
    if (!on) return;
    share = new PhoneShare(remote);
    share.start(phoneRoots(sharePhotos.get(), sharedFolders.get(), !limited), limited);
  };

  const update = () => {
    const state = remote.connection.state.get();
    if (state._tag === "Ready" && state.hello.mac !== null) name = state.hello.mac.name;
    if (ended(state)) releaseLink();
    describeLink(name ?? "Your Mac", lineOf(state, shareFiles.get()));
    serve();
  };

  const hold = () => {
    if (!ended(remote.connection.state.get())) void holdLink();
  };

  const stops = [remote.connection.state.subscribe(update), shareFiles.subscribe(update), sharePhotos.subscribe(serve), sharedFolders.subscribe(serve), linkHeld.subscribe(serve)];
  const appState = AppState.addEventListener("change", (next) => {
    active = next === "active";
    if (active) hold();
    serve();
  });
  update();
  if (active) hold();
  return () => {
    stops.forEach((stop) => stop());
    appState.remove();
    share?.stopServing();
  };
};

/**
 * Keeps the link to the Mac alive while paired, even with the app closed (Android), behind one
 * ongoing notification. It starts each time the app opens; Disconnect in the notification stops it
 * until the next open, and unpairing or the Mac removing this phone stops it for good. This lives
 * outside React on purpose: closing the app unmounts every screen, and that must not count as letting go.
 */
export const watchLink = (): void => {
  let stop: (() => void) | null = null;
  const onSession = () => {
    stop?.();
    stop = null;
    const session = sessions.session.get();
    if (session.status === "paired") stop = follow(session.remote);
    else releaseLink();
  };
  sessions.session.subscribe(onSession);
  onSession();
  linkHeld.subscribe(() => stayConnected.set(linkHeld.get()));
};
