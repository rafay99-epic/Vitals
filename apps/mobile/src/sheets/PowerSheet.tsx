import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { GRACE_SECONDS } from "@vitals/app/features/orders/labels.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import type { Command, RunningApp } from "@vitals/contracts";
import { useEffect, useState } from "react";

import { send, useAccess } from "../lib/remote.ts";
import { Hold, sheet, SheetCancel, SheetHeader, SheetNote, Tile, TileGrid } from "../ui/index.ts";

export type Ending = "Restart" | "LogOut" | "ShutDown";

const ENDING: Record<Ending, { readonly title: string; readonly hold: string; readonly command: Command }> = {
  ShutDown: { title: "Shut down your Mac?", hold: "Hold to shut down", command: { _tag: "ShutDown", graceSeconds: GRACE_SECONDS } },
  Restart: { title: "Restart your Mac?", hold: "Hold to restart", command: { _tag: "Restart", graceSeconds: GRACE_SECONDS } },
  LogOut: { title: "Log out of your Mac?", hold: "Hold to log out", command: { _tag: "LogOut", graceSeconds: GRACE_SECONDS } },
};

const APPS_SHOWN = 4;

const openAppsLine = (apps: ReadonlyArray<RunningApp> | "unknown" | null): string => {
  if (apps === null) return "Checking which apps are open.";
  if (apps === "unknown") return "Could not read the open apps. Unsaved work may be lost.";
  if (apps.length === 0) return "No apps are open.";
  const names = apps.slice(0, APPS_SHOWN).map((app) => app.name);
  const rest = apps.length - names.length;
  return `${names.join(", ")}${rest > 0 ? ` and ${String(rest)} more` : ""} ${apps.length === 1 ? "is" : "are"} open. They may ask to save first.`;
};

/** Hold-to-confirm sheet for the three actions that end a session on the Mac. */
function confirmSheet(ending: Ending) {
  return function ConfirmSheet() {
    const remote = useRemote();
    const spec = ENDING[ending];
    const [apps, setApps] = useState<ReadonlyArray<RunningApp> | "unknown" | null>(null);
    useEffect(() => {
      let live = true;
      void remote.connection.call((client) => client["apps.list"]({})).then((result) => {
        if (live) setApps(result.ok ? result.value.running : "unknown");
      });
      return () => {
        live = false;
      };
    }, [remote]);
    return (
      <>
        <SheetHeader title={spec.title} detail={openAppsLine(apps)} />
        <Hold
          label={spec.hold}
          onCommit={() => {
            sheet.close();
            void remote.run(spec.command);
          }}
        />
        <SheetNote>{`You get ${String(GRACE_SECONDS)} seconds to cancel.`}</SheetNote>
        <SheetCancel />
      </>
    );
  };
}

/** Power actions, reachable from the power button on Home. Mirrors Control's power tiles. */
export function PowerSheet() {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const name = state._tag === "Ready" && state.hello.mac !== null ? state.hello.mac.name : "Your Mac";
  return (
    <>
      <SheetHeader title="Power" detail={name} />
      <PowerTiles raised />
      <SheetCancel />
    </>
  );
}

/** Sleep, lock and screen off are taps. Restart, log out and shut down need a hold. */
export function PowerTiles({ raised = false }: { readonly raised?: boolean }) {
  const remote = useRemote();
  const access = useAccess();
  const now = (command: Command, done: string) => () => {
    sheet.close();
    void send(remote, command, done);
  };
  const end = (ending: Ending) => () => sheet.open(confirmSheet(ending));
  return (
    <>
      {access.operate || access.destructive ? null : <SheetNote>This phone can only watch. Turn on control for it in Vitals on the Mac.</SheetNote>}
      <TileGrid>
        <Tile icon="moon" label="Sleep" raised={raised} disabled={!access.operate} onPress={now({ _tag: "Sleep", graceSeconds: 0 }, "Your Mac is going to sleep")} />
        <Tile icon="lock" label="Lock" raised={raised} disabled={!access.operate} onPress={now({ _tag: "Lock" }, "Locked")} />
        <Tile icon="screen" label="Screen off" raised={raised} disabled={!access.operate} onPress={now({ _tag: "DisplayOff" }, "Screen is off")} />
        <Tile icon="restart" label="Restart" raised={raised} disabled={!access.destructive} onPress={end("Restart")} />
        <Tile icon="logout" label="Log out" raised={raised} disabled={!access.destructive} onPress={end("LogOut")} />
        <Tile icon="power" label="Shut down" danger raised={raised} disabled={!access.destructive} onPress={end("ShutDown")} />
      </TileGrid>
      {access.operate && !access.destructive ? <SheetNote>Restart, log out and shut down are off for this phone.</SheetNote> : null}
    </>
  );
}
