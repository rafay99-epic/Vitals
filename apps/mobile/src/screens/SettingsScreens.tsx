import { useFocusEffect } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { nearby, nearbyEndpoints } from "@vitals/app/connection/nearby.ts";
import { startTunnel, tailnetSupported, tunnel } from "@vitals/app/connection/tunnel.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { Diagnostics } from "@vitals/app/features/diagnostics/DiagnosticsScreen.tsx";
import { checkPlay, playState, playSupported, startPlayUpdate } from "@vitals/app/features/updates/playUpdate.ts";
import { updateInfo } from "@vitals/app/features/updates/updateInfo.ts";
import { deviceInfo } from "@vitals/app/lib/device.ts";
import { hostOf } from "@vitals/app/lib/host.ts";
import { TAILSCALE_STORE_URL } from "@vitals/app/lib/links.ts";
import { isDevBuild } from "@vitals/app/lib/variant.ts";
import { notificationPermission, requestNotifications } from "@vitals/app/notifications/alerts.ts";
import { startAlertWatch } from "@vitals/app/notifications/background.ts";
import type { PermissionState } from "@vitals/app/notifications/permission.ts";
import { CLIENT_VERSION } from "@vitals/app/state/remote.ts";
import { useScopes } from "@vitals/app/state/useScopes.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useLink } from "@vitals/app/state/useVitals.ts";
import type { Scope } from "@vitals/contracts";
import { formatDateTime } from "@vitals/shared";
import Constants from "expo-constants";
import { useCallback, useEffect, useState } from "react";
import { Linking, StyleSheet, View } from "react-native";

import { LINK_COLOR, useMac } from "../lib/remote.ts";
import { checkForUpdate, restartIntoUpdate, type UpdateState, updateState } from "../lib/updates.ts";
import type { SettingsStackParams } from "../navigation.ts";
import { UnpairSheet } from "../sheets/SendSheets.tsx";
import { BackBar, BigButton, color, Group, Label, Note, Page, Row, sheet, T, Title, toast } from "../ui/index.ts";

type Props<K extends keyof SettingsStackParams> = NativeStackScreenProps<SettingsStackParams, K>;

const GB = 1024 ** 3;

const PERMISSION: Record<PermissionState, string> = {
  granted: "On",
  prompt: "Off",
  denied: "Blocked",
  unsupported: "Not here",
};

const usePermission = (): [PermissionState | null, () => void] => {
  const [permission, setPermission] = useState<PermissionState | null>(null);
  const refresh = useCallback(() => void notificationPermission().then(setPermission), []);
  useFocusEffect(refresh);
  return [permission, refresh];
};

const UPDATE_WORD: Record<UpdateState["_tag"], string> = {
  Off: "Off in this build",
  Idle: "Not checked yet",
  Checking: "Checking",
  Downloading: "Downloading",
  Ready: "Ready to install",
  Current: "Up to date",
  Failed: "Update failed",
};

export function SettingsScreen({ navigation }: Props<"Settings">) {
  const remote = useRemote();
  const mac = useMac();
  const link = useLink();
  const update = useStore(updateState);
  const [permission] = usePermission();
  return (
    <Page>
      <Title>Settings.</Title>
      <View style={styles.mac}>
        <T v="heading">{mac?.name ?? "Your Mac"}</T>
        <T v="small">{mac === null ? "Connecting" : `${mac.chip} · ${String(Math.round(mac.memoryBytes / GB))} GB · ${mac.os} · Vitals ${mac.vitalsVersion}`}</T>
      </View>
      <Group>
        <Row first label="Connection" value={link.label} valueColor={LINK_COLOR[link.tone]} onPress={() => navigation.navigate("Connection")} />
        <Row label="Notifications" value={permission === null ? "" : PERMISSION[permission]} onPress={() => navigation.navigate("Notifications")} />
        <Row label="Updates" value={UPDATE_WORD[update._tag]} valueColor={update._tag === "Ready" ? color.yellow : color.dim} onPress={() => navigation.navigate("Updates")} />
      </Group>
      <Group>
        <Row first label="This phone" value={deviceInfo().name} onPress={() => navigation.navigate("Phone")} />
        <Row label="Help" onPress={() => navigation.navigate("Help")} />
      </Group>
      <Group>
        <Row first danger label="Unpair this phone" detail={`Paired ${formatDateTime(remote.credentials.pairedAt)}`} onPress={() => sheet.open(UnpairSheet)} />
      </Group>
    </Page>
  );
}

/** The innermost cause of a native error chain, without the Java wrapper text. */
const causeOf = (reason: string): string => (reason.split(/Caused by:\s*/).at(-1) ?? reason).replace(/^[\w.$]+:\s*/, "").trim();

function BuiltInTailscale() {
  const remote = useRemote();
  const state = useStore(tunnel);
  const link = useStore(remote.link);
  const press = () => {
    if (state._tag === "NeedsLogin") return void Linking.openURL(state.url);
    remote.setBuiltInTailscale(true);
    void startTunnel({ ...link, builtInTailscale: true });
  };
  const value = { Off: "Turn on", Starting: "Starting", NeedsLogin: "Sign in", Ready: "On", Failed: "Try again" }[state._tag];
  const idle = state._tag === "Ready" || state._tag === "Starting";
  return <Row label="Built-in Tailscale" detail={state._tag === "Failed" ? `Could not start: ${causeOf(state.reason)}` : "No Tailscale app needed"} value={value} valueColor={state._tag === "Ready" ? color.blue : color.ink} onPress={idle ? undefined : press} />;
}

interface RouteRow {
  readonly detail: string;
  readonly value: string;
  readonly color: string;
}

/** Plain-language status for each route, from the live connection and the saved pairing. */
const useRoutes = (): { readonly wifi: RouteRow; readonly away: RouteRow; readonly latency: string | null; readonly hasAway: boolean } => {
  const remote = useRemote();
  const link = useStore(remote.link);
  const state = useStore(remote.connection.state);
  useStore(nearby);
  const route = state._tag === "Ready" ? state.route : null;
  const lan = nearbyEndpoints(link.macKey)[0] ?? link.lan?.[0];
  const wifiValue = route === "lan" ? "In use" : lan === undefined ? "Not on this Wi-Fi" : "Ready";
  const awayValue = route === "tailnet" ? "In use" : link.baseUrl === null ? "Not set up" : "Ready as backup";
  return {
    wifi: { detail: lan === undefined ? "Not on the Mac's Wi-Fi" : `${lan.host} · encrypted`, value: wifiValue, color: route === "lan" ? color.green : color.dim },
    away: { detail: link.baseUrl === null ? "Reach the Mac away from home" : hostOf(link.baseUrl), value: awayValue, color: route === "tailnet" ? color.blue : color.dim },
    latency: state._tag === "Ready" && state.latencyMs !== null ? `${String(state.latencyMs)} ms` : null,
    hasAway: link.baseUrl !== null,
  };
};

export function ConnectionScreen() {
  const remote = useRemote();
  const { wifi, away, latency, hasAway } = useRoutes();
  return (
    <Page>
      <BackBar parent="Settings" />
      <Title>Connection.</Title>
      <Group>
        <Row first label="Wi-Fi" detail={wifi.detail} value={wifi.value} valueColor={wifi.color} />
        <Row label="Tailscale" detail={away.detail} value={away.value} valueColor={away.color} />
        {latency === null ? null : <Row label="Round trip" value={latency} />}
        {tailnetSupported && hasAway ? <BuiltInTailscale /> : null}
      </Group>
      <Note>At home Vitals uses Wi-Fi. Away, it switches to Tailscale on its own.</Note>
      {hasAway ? null : <Note>To set up away access, open Vitals on the Mac, then Remote, then Tailscale.</Note>}
      <BigButton ghost label="Check routes now" onPress={() => remote.connection.wake("manual")} />
      {hasAway && !tailnetSupported ? <BigButton ghost label="Get Tailscale for this phone" onPress={() => void Linking.openURL(TAILSCALE_STORE_URL)} /> : null}
    </Page>
  );
}

export function NotificationsScreen() {
  const [permission, refresh] = usePermission();
  const allow = () =>
    void requestNotifications().then(async (granted) => {
      if (granted) await startAlertWatch();
      refresh();
    });
  return (
    <Page>
      <BackBar parent="Settings" />
      <Title>Notifications.</Title>
      <Group>
        <Row first label="Alerts from your Mac" detail="When memory, heat or agents need a hand" value={permission === null ? "" : PERMISSION[permission]} valueColor={permission === "granted" ? color.green : color.dim} />
      </Group>
      {permission === "prompt" ? <BigButton label="Turn on notifications" onPress={allow} /> : null}
      {permission === "denied" ? (
        <>
          <Note>Notifications are blocked for Vitals in your phone settings.</Note>
          <BigButton ghost label="Open phone settings" onPress={() => void Linking.openSettings()} />
        </>
      ) : null}
      <Note>Which problems raise an alert is set in Alerts, under Tell me when.</Note>
    </Page>
  );
}

function PlayRow() {
  const play = useStore(playState);
  useEffect(() => {
    void checkPlay();
  }, []);
  if (!playSupported) return null;
  const value = { Unchecked: "Checking", Current: "Up to date", Available: "Update available", Downloading: "Downloading", Unavailable: "Not available" }[play._tag];
  return (
    <>
      <Row label="Google Play" detail={play._tag === "Unavailable" ? play.reason : "Bigger updates come from the store"} value={value} valueColor={play._tag === "Available" ? color.yellow : color.dim} />
      {play._tag === "Available" ? <BigButton label="Update from Google Play" onPress={() => void startPlayUpdate().then((ok) => ok || toast.show("Google Play did not open. Try again.", { tone: "bad" }))} /> : null}
    </>
  );
}

export function UpdatesScreen() {
  const update = useStore(updateState);
  const info = updateInfo();
  return (
    <Page>
      <BackBar parent="Settings" />
      <Title>Updates.</Title>
      <Group>
        <Row first label="Vitals Remote" value={`${Constants.expoConfig?.version ?? CLIENT_VERSION} · ${info.running}`} />
        <Row label="Status" detail={update._tag === "Failed" ? update.reason : undefined} value={UPDATE_WORD[update._tag]} valueColor={update._tag === "Ready" ? color.yellow : color.dim} />
        <PlayRow />
      </Group>
      {update._tag === "Ready" ? (
        <>
          <BigButton label="Restart to update" onPress={() => void restartIntoUpdate()} />
          <Note>Takes a second. The screen stays dark and your Mac is not touched.</Note>
        </>
      ) : null}
      {update._tag !== "Off" && update._tag !== "Ready" ? <BigButton ghost label="Check now" disabled={update._tag === "Checking" || update._tag === "Downloading"} onPress={() => void checkForUpdate(true)} /> : null}
      <Note>Updates download in the background and install the next time you open the app. Nothing blocks you.</Note>
    </Page>
  );
}

const SCOPES: ReadonlyArray<{ readonly scope: Scope; readonly label: string }> = [
  { scope: "read", label: "See readings" },
  { scope: "operate", label: "Control the Mac" },
  { scope: "destructive", label: "Shut down, restart, quit apps" },
  { scope: "clipboard", label: "Read the Mac clipboard" },
];

export function PhoneScreen() {
  const remote = useRemote();
  const scopes = useScopes();
  return (
    <Page>
      <BackBar parent="Settings" />
      <Title>This phone.</Title>
      <Group>
        <Row first label="Name" value={deviceInfo().name} />
        <Row label="Paired" value={formatDateTime(remote.credentials.pairedAt)} />
      </Group>
      <Label>What it can do</Label>
      <Group>
        {SCOPES.map((item, index) => (
          <Row key={item.scope} first={index === 0} label={item.label} value={scopes.includes(item.scope) ? "Allowed" : "Off"} valueColor={scopes.includes(item.scope) ? color.green : color.dim} />
        ))}
      </Group>
      <Note>Change this in Vitals on the Mac, under Remote.</Note>
    </Page>
  );
}

export function HelpScreen({ navigation }: Props<"Help">) {
  const link = useLink();
  return (
    <Page>
      <BackBar parent="Settings" />
      <Title>Help.</Title>
      <Group>
        <Row first label="App version" value={`${Constants.expoConfig?.version ?? CLIENT_VERSION}`} />
        <Row label="Connection" value={link.label} />
        {isDevBuild ? <Row label="Diagnostics" detail="Frame rate, calls, memory" onPress={() => navigation.navigate("Diagnostics")} /> : null}
      </Group>
      <Note>Vitals Remote shows what Vitals on your Mac reads. Keep Vitals running on the Mac, with Remote turned on.</Note>
    </Page>
  );
}

export function DiagnosticsRoute({ navigation }: Props<"Diagnostics">) {
  return <Diagnostics parent="Help" onBack={() => navigation.goBack()} />;
}

const styles = StyleSheet.create({
  mac: { marginHorizontal: 16, marginBottom: 12, padding: 16, borderRadius: 18, backgroundColor: color.s2, gap: 4 },
});
