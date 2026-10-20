import { useFocusEffect } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import type { AppsSnapshot, Emulator, RunningApp } from "@vitals/contracts";
import { formatDateTime } from "@vitals/shared";
import { Button, EmptyState, Field, HoldRow, Row, Screen, Section, Sheet, SheetAction } from "@vitals/ui";
import { useCallback, useState } from "react";
import { View } from "react-native";

import { TabHeader } from "../../components/TabHeader.tsx";
import { sessions } from "../../connection/session.ts";
import { useRemote } from "../../connection/useRemote.ts";
import { deviceInfo } from "../../lib/device.ts";
import { haptics } from "../../lib/haptics";
import { hostOf } from "../../lib/host.ts";
import type { RecordStackParams } from "../../navigation/types.ts";
import { notificationPermission, requestNotifications } from "../../notifications/alerts";
import { startAlertWatch } from "../../notifications/background";
import type { PermissionState } from "../../notifications/permission.ts";
import { CONSENT_HINT, scopeLine } from "../../state/commands.ts";
import { useScopes } from "../../state/useScopes.ts";
import { useStore } from "../../state/useStore.ts";
import { DiagnosticsEntry } from "../diagnostics/DiagnosticsEntry";
import { UpdatesSection } from "../updates/UpdatesSection";

type Props = NativeStackScreenProps<RecordStackParams, "Record">;

type Focus = { readonly kind: "app"; readonly app: RunningApp } | { readonly kind: "emulator"; readonly emulator: Emulator } | { readonly kind: "unpair" };

const PERMISSION: Record<PermissionState, string> = {
  granted: "Ready",
  prompt: "Tap to allow",
  denied: "Off in system settings",
  unsupported: "Not supported here",
};

const appDetail = (app: RunningApp): string | undefined => {
  if (app.active) return "frontmost";
  return app.hidden ? "hidden" : undefined;
};

function AppsPending({ error }: { readonly error: string | null }) {
  if (error === null) return <EmptyState title="Reading the Mac." />;
  return <EmptyState title="Could not read the Mac." detail={error} />;
}

export function RecordScreen({ navigation }: Props) {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const scopes = useScopes();
  const destructive = scopes.includes("destructive");
  const operate = scopes.includes("operate");
  const [apps, setApps] = useState<AppsSnapshot | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [permission, setPermission] = useState<PermissionState | null>(null);
  const [bundleId, setBundleId] = useState("");
  const [focus, setFocus] = useState<Focus | null>(null);

  const ready = state._tag === "Ready";
  const [appsError, setAppsError] = useState<string | null>(null);

  const refresh = useCallback(() => {
    void notificationPermission().then(setPermission);
    return remote.connection.call((client) => client["apps.list"]({})).then((result) => {
      if (result.ok) setApps(result.value);
      setAppsError(result.ok ? null : result.error.message);
    });
  }, [remote]);

  useFocusEffect(
    useCallback(() => {
      if (ready) void refresh();
    }, [ready, refresh]),
  );

  const pull = () => {
    setRefreshing(true);
    void refresh().finally(() => setRefreshing(false));
  };

  const close = () => setFocus(null);
  const order = (run: () => Promise<unknown>) => {
    haptics.success();
    close();
    void run().then(refresh);
  };

  const allowAlerts = () =>
    void requestNotifications().then(async (granted) => {
      if (granted) await startAlertWatch();
      setPermission(await notificationPermission());
    });

  const mac = state._tag === "Ready" ? state.hello.mac : null;
  const running = apps?.running ?? [];
  const emulators = apps?.emulators ?? [];

  return (
    <Screen top={<TabHeader title="Record." meta={`Paired ${formatDateTime(remote.credentials.pairedAt)} · ${scopeLine(scopes)}`} />} refreshing={refreshing} onRefresh={pull}>
      <Section title="Mac">
        <Row plain label="Name" value={mac?.name ?? "--"} />
        <Row plain label="Model" value={mac === null ? "--" : `${mac.chip} · ${mac.model}`} />
        <Row plain label="macOS" value={mac?.os ?? "--"} />
        <Row plain label="Vitals" value={mac === null ? "--" : `${mac.vitalsVersion} (${mac.channel})`} />
        <Row plain label="Address" detail={hostOf(remote.credentials.baseUrl)} />
      </Section>

      <Section title="This device">
        <Row plain label="Name" value={deviceInfo().name} />
        <Row plain label="Paired" value={formatDateTime(remote.credentials.pairedAt)} />
        <Row plain label="Scope" value={scopeLine(scopes)} />
      </Section>

      <UpdatesSection />

      <Section title="Permissions">
        <Row plain label="Alerts" value={permission === null ? "--" : PERMISSION[permission]} valueTone={permission === "granted" ? "pulse" : "ink"} onPress={permission === "prompt" ? allowAlerts : undefined} />
      </Section>

      <Section title="Running apps" trailing={`${String(running.length)} open`}>
        {apps === null ? <AppsPending error={appsError} /> : null}
        {running.map((app) => (
          <Row key={app.pid} label={app.name} detail={appDetail(app)} onPress={operate ? () => setFocus({ kind: "app", app }) : undefined} />
        ))}
      </Section>

      <Section title="Launch">
        <Field label="Bundle id" mono value={bundleId} onChangeText={setBundleId} placeholder="com.apple.Safari" autoCapitalize="none" autoCorrect={false} editable={operate} />
        <View className="px-[22px] pb-4">
          <Button label="Launch" variant="line" small disabled={!operate || bundleId.trim().length === 0} onPress={() => order(() => remote.run({ _tag: "LaunchApp", bundleId: bundleId.trim() }))} />
        </View>
      </Section>

      <Section title="Emulators" trailing={apps === null ? undefined : `${String(emulators.length)} running`}>
        {apps === null ? <AppsPending error={appsError} /> : null}
        {apps !== null && emulators.length === 0 ? <EmptyState title="None running." /> : null}
        {emulators.map((emulator) => (
          <Row key={`${emulator.kind}-${emulator.id}`} label={emulator.name} detail={`${emulator.kind} · ${emulator.id}`} value={destructive ? "Stop" : undefined} onPress={destructive ? () => setFocus({ kind: "emulator", emulator }) : undefined} />
        ))}
      </Section>

      <DiagnosticsEntry onOpen={() => navigation.navigate("Diagnostics")} />

      <Section title="Leave">
        <Row label="Unpair" tone="press" detail="needs a new code from the Mac" onPress={() => setFocus({ kind: "unpair" })} />
      </Section>

      <FocusSheet focus={focus} destructive={destructive} onClose={close} order={order} />
    </Screen>
  );
}

function FocusSheet({
  focus,
  destructive,
  onClose,
  order,
}: {
  readonly focus: Focus | null;
  readonly destructive: boolean;
  readonly onClose: () => void;
  readonly order: (run: () => Promise<unknown>) => void;
}) {
  const remote = useRemote();
  if (focus?.kind === "app") {
    const ref = { pid: focus.app.pid, bundleId: focus.app.bundleId };
    return (
      <Sheet visible title={focus.app.name} detail={focus.app.bundleId ?? `pid ${String(focus.app.pid)}`} onClose={onClose}>
        <SheetAction label="Hide" detail="keeps running" onPress={() => order(() => remote.run({ _tag: "HideApp", app: ref }))} />
        <SheetAction label="Quit" detail="asks the app to close" onPress={() => order(() => remote.run({ _tag: "QuitApp", app: ref }))} />
        {destructive ? (
          <HoldRow label="Force quit" hint={`unsaved work is lost · ${CONSENT_HINT}`} kind="consent" danger compact onStart={haptics.soft} onCommit={() => order(() => remote.run({ _tag: "ForceQuitApp", app: ref }))} />
        ) : null}
      </Sheet>
    );
  }
  if (focus?.kind === "emulator") {
    const { kind, id, name } = focus.emulator;
    return (
      <Sheet visible title={name} detail={`${kind} · ${id}`} onClose={onClose}>
        <HoldRow label="Stop" hint={`shuts the device down · ${CONSENT_HINT}`} kind="consent" danger compact onStart={haptics.soft} onCommit={() => order(() => remote.run({ _tag: "StopEmulator", kind, id }))} />
      </Sheet>
    );
  }
  return (
    <Sheet visible={focus?.kind === "unpair"} title="Unpair this device?" detail="You will need a new code from the Mac." onClose={onClose}>
      <HoldRow
        label="Unpair"
        hint={`revokes this device · ${CONSENT_HINT}`}
        kind="consent"
        danger
        compact
        onStart={haptics.soft}
        onCommit={() => {
          haptics.heavy();
          onClose();
          void sessions.forget();
        }}
      />
    </Sheet>
  );
}
