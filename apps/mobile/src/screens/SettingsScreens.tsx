import { useFocusEffect } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { nearby, nearbyEndpoints } from "@vitals/app/connection/nearby.ts";
import { startTunnel, tailnetSupported, tunnel } from "@vitals/app/connection/tunnel.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { Diagnostics } from "@vitals/app/features/diagnostics/DiagnosticsScreen.tsx";
import { deviceInfo } from "@vitals/app/lib/device.ts";
import { hostOf } from "@vitals/app/lib/host.ts";
import { TAILSCALE_STORE_URL } from "@vitals/app/lib/links.ts";
import { isStoreBuild } from "@vitals/app/lib/variant.ts";
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
import { AppState, Linking, Platform, StyleSheet, View } from "react-native";

import { LINK_COLOR, useMac } from "../lib/remote.ts";
import { errorReports, setErrorReports } from "../lib/reporting.ts";
import { holdsInBackground } from "../../modules/vitals-share/index.ts";
import { askFullStorage, hasFullStorage, phoneRoots, pickSharedFolder, removeSharedFolder, setSharePhotos, shareThisPhone, sharedFolders, shareFiles, sharePhotos } from "../lib/share.ts";
import { openCheck } from "../ConnectionCheck.tsx";
import type { SettingsStackParams } from "../navigation.ts";
import { UnpairSheet } from "../sheets/SendSheets.tsx";
import { useUpdateStatus } from "../UpdateSync.tsx";
import { BackBar, BigButton, color, Group, Label, Note, Page, Row, sheet, T, Title, toast, Toggle } from "../ui/index.ts";

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

export function SettingsScreen({ navigation }: Props<"Settings">) {
  const remote = useRemote();
  const mac = useMac();
  const link = useLink();
  const update = useUpdateStatus();
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
        <Row label="Updates" value={update.word} valueColor={update.waiting ? color.yellow : color.dim} onPress={() => navigation.navigate("Updates")} />
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
      <BigButton ghost label="Check connection" onPress={openCheck} />
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

const SCOPES: ReadonlyArray<{ readonly scope: Scope; readonly label: string }> = [
  { scope: "read", label: "See readings" },
  { scope: "operate", label: "Control the Mac" },
  { scope: "destructive", label: "Shut down, restart, quit apps" },
  { scope: "clipboard", label: "Read the Mac clipboard" },
  { scope: "files", label: "Send and get files" },
  { scope: "fsRead", label: "Browse the Mac's folders" },
  { scope: "fsWrite", label: "Change the Mac's files" },
  { scope: "terminal", label: "Terminal" },
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
      <ShareSettings />
    </Page>
  );
}

function ShareSettings() {
  const sharing = useStore(shareFiles);
  const [full, setFull] = useState(hasFullStorage);
  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => state === "active" && setFull(hasFullStorage()));
    return () => subscription.remove();
  }, []);
  if (Platform.OS === "ios") return <ShareIphone sharing={sharing} />;
  const roots = phoneRoots();
  return (
    <>
      <Label>What your Mac can see here</Label>
      <Group>
        <Row first label="Let your Mac and other phones browse" control={<Toggle value={sharing} label="Let your Mac and other phones browse" onChange={shareThisPhone} />} />
        <Row label="All files on this phone" value={full ? "Allowed" : "Off"} valueColor={full ? color.green : color.dim} onPress={() => void askFullStorage()} />
      </Group>
      <Note>{sharing ? `Shared ${holdsInBackground ? "until you turn this off, even with Vitals closed" : "while Vitals is open"}: ${roots.map((root) => root.label).join(", ")}.` : "Nothing on this phone is shared."}</Note>
    </>
  );
}

const showPhotos = (on: boolean) =>
  void setSharePhotos(on).then((access) => {
    if (access === "denied") toast.show("iOS keeps Photos from Vitals. Allow it in Settings.", { tone: "bad", action: "Open", onAction: () => void Linking.openSettings() });
  });

const pick = (role: "downloads" | "documents" | "other") =>
  void pickSharedFolder(role).then((folder) => folder !== null && toast.show(`${folder.name} is shared`));

/** iPhone: Photos through PhotoKit, plus folders picked once in Files. Only while Vitals is open. */
function ShareIphone({ sharing }: { readonly sharing: boolean }) {
  const photos = useStore(sharePhotos);
  const folders = useStore(sharedFolders);
  const downloads = folders.find((folder) => folder.role === "downloads");
  const documents = folders.find((folder) => folder.role === "documents");
  const others = folders.filter((folder) => folder.role === "other");
  return (
    <>
      <Label>Share this iPhone</Label>
      <Group>
        <Row first label="Let your Mac and other phones browse" control={<Toggle value={sharing} label="Let your Mac and other phones browse" onChange={shareThisPhone} />} />
        <Row label="Photos and screenshots" control={<Toggle value={photos} label="Share photos and screenshots" onChange={showPhotos} />} />
        <Row label="Downloads folder" value={downloads?.name ?? "Pick"} onPress={() => pick("downloads")} />
        <Row label="Documents folder" value={documents?.name ?? "Pick"} onPress={() => pick("documents")} />
        {others.map((folder) => (
          <Row key={folder.id} label={folder.name} value="Remove" valueColor={color.red} onPress={() => void removeSharedFolder(folder.id)} />
        ))}
        <Row label="Add folder" detail="iCloud Drive or On My iPhone" onPress={() => pick("other")} />
      </Group>
      <Note>{sharing ? "Your Mac and other phones can see these only while Vitals is open here." : "Nothing on this iPhone is shared."}</Note>
    </>
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
        {isStoreBuild ? null : <Row label="Diagnostics" detail="Frame rate, calls, memory" onPress={() => navigation.navigate("Diagnostics")} />}
      </Group>
      <Note>Vitals Remote shows what Vitals on your Mac reads. Keep Vitals running on the Mac, with Remote turned on.</Note>
      <ErrorReports />
    </Page>
  );
}

/** Where crashes and errors go: always the paired Mac's Activity log, and Sentry unless turned off. */
function ErrorReports() {
  const remote = useRemote();
  const reports = useStore(errorReports);
  const clear = () =>
    void remote.clearLogs().then((removed) => toast.show(removed === null ? "Cleared on this phone. Connect to clear your Mac's copy." : "Cleared here and on your Mac"));
  return (
    <>
      <Label>Errors</Label>
      <Group>
        <Row first label="Send error reports" control={<Toggle value={reports} label="Send error reports" onChange={setErrorReports} />} />
        <Row danger label="Clear error logs" detail="On this phone and your Mac" onPress={clear} />
      </Group>
      <Note>Crashes and errors go to your Mac's Activity log for 30 days. With reports on, they also go to Sentry so we can fix them, with file names, folders and addresses removed.</Note>
    </>
  );
}

export function DiagnosticsRoute({ navigation }: Props<"Diagnostics">) {
  return <Diagnostics parent="Help" onBack={() => navigation.goBack()} />;
}

const styles = StyleSheet.create({
  mac: { marginHorizontal: 16, marginBottom: 12, padding: 16, borderRadius: 18, backgroundColor: color.s2, gap: 4 },
});
