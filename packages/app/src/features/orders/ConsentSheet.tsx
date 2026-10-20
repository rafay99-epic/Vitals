import type { Command, RunningApp } from "@vitals/contracts";
import { HoldRow, Mono, Sheet } from "@vitals/ui";
import { useEffect, useState } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";
import { CONSENT_HINT } from "../../state/commands.ts";
import { useStore } from "../../state/useStore.ts";
import { GRACE_SECONDS } from "./labels.ts";

export type Discharge = "Restart" | "LogOut" | "ShutDown";

export const DISCHARGE: Record<Discharge, { readonly label: string; readonly question: string; readonly command: Command }> = {
  Restart: { label: "Restart", question: "Restart?", command: { _tag: "Restart", graceSeconds: GRACE_SECONDS } },
  LogOut: { label: "Log out", question: "Log out?", command: { _tag: "LogOut", graceSeconds: GRACE_SECONDS } },
  ShutDown: { label: "Shut down", question: "Shut down?", command: { _tag: "ShutDown", graceSeconds: GRACE_SECONDS } },
};

const APPS_SHOWN = 6;

type OpenApps = ReadonlyArray<RunningApp> | "unknown" | null;

const appsLine = (apps: OpenApps): string => {
  if (apps === null) return "Checking open apps.";
  if (apps === "unknown") return "Could not read the open apps. Unsaved work may be lost.";
  if (apps.length === 0) return "No apps are open.";
  const names = apps.slice(0, APPS_SHOWN).map((app) => app.name).join(", ");
  return apps.length > APPS_SHOWN ? `Open: ${names} and ${String(apps.length - APPS_SHOWN)} more. Each may ask to save.` : `Open: ${names}. Each may ask to save.`;
};

export function ConsentSheet({ order, onClose }: { readonly order: Discharge | null; readonly onClose: () => void }) {
  const remote = useRemote();
  const [loaded, setLoaded] = useState<{ readonly order: Discharge; readonly apps: ReadonlyArray<RunningApp> | "unknown" } | null>(null);
  const apps = loaded !== null && loaded.order === order ? loaded.apps : null;

  useEffect(() => {
    if (order === null) return;
    let live = true;
    void remote.connection.call((client) => client["apps.list"]({})).then((result) => {
      if (live) setLoaded({ order, apps: result.ok ? result.value.running : "unknown" });
    });
    return () => {
      live = false;
    };
  }, [order, remote]);

  const spec = order === null ? null : DISCHARGE[order];
  const mac = useStore(remote.connection.state);
  const name = mac._tag === "Ready" && mac.hello.mac !== null ? mac.hello.mac.name : "your Mac";

  return (
    <Sheet visible={spec !== null} title={spec?.question ?? ""} detail={`${name} · ${String(GRACE_SECONDS)} s to cancel after`} onClose={onClose}>
      <View className="px-[22px] pb-4">
        <Mono tone="ink2" className="leading-5">
          {appsLine(apps)}
        </Mono>
      </View>
      {spec === null ? null : (
        <HoldRow
          label={spec.label}
          hint={CONSENT_HINT}
          kind="consent"
          danger
          onStart={haptics.soft}
          onCommit={() => {
            haptics.heavy();
            void remote.run(spec.command);
            onClose();
          }}
        />
      )}
    </Sheet>
  );
}
