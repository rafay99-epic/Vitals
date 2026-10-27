import { CLIENT_VERSION } from "@vitals/app/state/remote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { formatDateTime } from "@vitals/shared";
import Constants from "expo-constants";
import { useEffect } from "react";
import { Linking, StyleSheet, View } from "react-native";

import { checkNightly, installedBuild, nightlyState, nightlySupported } from "../lib/nightly.ts";
import { checkPlay, installPlay, playSupported, startPlay } from "../lib/play.ts";
import { playVersion, QUICK_UPDATES, type UpdateView } from "../lib/updateModel.ts";
import { checkForUpdate, downloadUpdate, quickUpdates, restartIntoUpdate, setQuickUpdates, thisLaunch, updateState } from "../lib/updates.ts";
import { useUpdateStatus } from "../UpdateSync.tsx";
import { BackBar, Bar, BigButton, Card, color, Group, Icon, Label, Note, Page, Row, Segmented, T, Title, toast } from "../ui/index.ts";

interface Copy {
  readonly title: string;
  readonly detail: string;
  readonly tone?: string;
}

const copyOf = (view: UpdateView): Copy => {
  switch (view.kind) {
    case "off":
      return { title: "Updates are off in this build", detail: "Store and Nightly builds update themselves." };
    case "current":
      return { title: "You're up to date", detail: view.checked ? "Checked just now." : "Vitals checks by itself when you open it." };
    case "checking":
      return { title: "Checking for updates", detail: playSupported ? "Quick updates and Google Play." : "Quick updates." };
    case "found":
      return { title: "Quick update ready to download", detail: view.notes === "" ? "You asked to be asked first." : view.notes };
    case "downloading":
      return { title: "Downloading a quick update", detail: "Keep using the app, it carries on." };
    case "ready":
      return { title: "Ready to install", detail: `${view.notes === "" ? "" : `${view.notes} `}Vitals restarts in about a second. Your Mac isn't touched.` };
    case "failed":
      return view.step === "check" ? { title: "Couldn't check", detail: view.reason, tone: color.red } : { title: "Download stopped", detail: view.reason, tone: color.red };
    case "play-found":
      return { title: "New version on Google Play", detail: `Vitals Remote ${playVersion(view.version)}, with changes a quick update can't carry.` };
    case "play-downloading":
      return { title: "Downloading from Google Play", detail: "Keep using the app, it carries on." };
    case "play-stopped":
      return view.reason === "blocked" ? { title: "Android paused the download", detail: "Charge your phone or free up space, then try again.", tone: color.orange } : { title: "Download stopped", detail: "Try again in a moment.", tone: color.red };
    case "play-ready":
      return { title: "Downloaded from Google Play", detail: "Restart to install. Vitals reopens where you were." };
    case "rolled-back":
      return { title: "Back on the previous version", detail: "The last quick update didn't start, so Vitals went back. Nothing on your Mac changed." };
  }
};

const check = () => {
  void checkForUpdate(true);
  void checkPlay(true);
  void checkNightly();
};

const playStarted = (started: boolean) => started || toast.show("Google Play did not open. Try again.", { tone: "bad" });

/** The buttons under the status. At most two: the step forward, and Check when nothing waits. */
function Actions({ view }: { readonly view: UpdateView }) {
  const quick = useStore(updateState);
  switch (view.kind) {
    case "off":
      return null;
    case "current":
    case "failed":
    case "rolled-back":
      return <BigButton ghost label="Check for updates" onPress={check} />;
    case "checking":
      return <BigButton ghost disabled label="Checking" onPress={check} />;
    case "downloading":
    case "play-downloading":
      return <BigButton ghost disabled label="Downloading" onPress={check} />;
    case "found":
      return quick._tag === "Found" ? <BigButton label="Download" onPress={() => void downloadUpdate(quick.id, quick.notes)} /> : null;
    case "ready":
      return <BigButton label="Restart now" onPress={() => void restartIntoUpdate()} />;
    case "play-found":
    case "play-stopped":
      return <BigButton label={view.kind === "play-found" ? "Update" : "Try again"} onPress={() => void startPlay().then(playStarted)} />;
    case "play-ready":
      return <BigButton label="Restart to install" onPress={installPlay} />;
  }
};

const PROGRESS: Partial<Record<UpdateView["kind"], true>> = { downloading: true, "play-downloading": true };

/** Settings > Updates: this version, one status in plain words, the next step, and how quick updates download. */
export function UpdatesScreen() {
  const { view } = useUpdateStatus();
  const choice = useStore(quickUpdates);
  const nightly = useStore(nightlyState);
  const copy = copyOf(view);
  const progress = "progress" in view ? view.progress : null;

  useEffect(() => {
    void checkPlay();
    void checkNightly();
  }, []);

  const from = thisLaunch.createdAt === null ? "Built in" : `Quick update from ${formatDateTime(thisLaunch.createdAt)}${thisLaunch.id === null ? "" : ` · ${thisLaunch.id}`}`;

  return (
    <Page>
      <BackBar parent="Settings" />
      <Title>Updates.</Title>
      <View style={styles.version}>
        <T v="monoStrong">{`Vitals Remote ${Constants.expoConfig?.version ?? CLIENT_VERSION}`}</T>
        <T v="small">{from}</T>
      </View>
      <Card tone="quiet">
        <View style={styles.status}>
          {view.kind === "current" ? <Icon name="check" size={16} color={color.yellow} /> : null}
          <T v="strong" color={copy.tone ?? color.ink} style={styles.statusTitle}>
            {copy.title}
          </T>
        </View>
        <T v="small">{copy.detail}</T>
        {progress !== null && PROGRESS[view.kind] === true ? (
          <View style={styles.progress}>
            <Bar value={progress} />
            <T v="mono" color={color.dim}>{`${String(Math.round(progress * 100))}%`}</T>
          </View>
        ) : null}
      </Card>
      <Actions view={view} />
      {nightlySupported && nightly._tag === "Available" ? <BigButton ghost label={`Download Nightly build ${String(nightly.build)}`} onPress={() => void Linking.openURL(nightly.url)} /> : null}
      {view.kind === "off" ? null : (
        <>
          <Label>Download quick updates</Label>
          <Segmented options={QUICK_UPDATES} value={choice} onChange={setQuickUpdates} />
        </>
      )}
      <Label>Where updates come from</Label>
      <Group>
        <Row first label="Quick updates" detail="Small fixes, in seconds" value="Over the air" />
        {playSupported ? <Row label="App updates" detail="New native builds" value="Google Play" /> : null}
        {nightlySupported ? <Row label="Nightly builds" detail={`Build ${String(installedBuild)} installed`} value="GitHub" /> : null}
      </Group>
      <Note>A downloaded quick update also installs by itself the next time you open Vitals.</Note>
    </Page>
  );
}

/** Home, when the Mac's Vitals speaks a newer protocol than this app: the one way forward is an update. */
export function UpdateNeeded({ who }: { readonly who: string }) {
  const { view } = useUpdateStatus();
  const nightly = useStore(nightlyState);
  useEffect(check, []);
  return (
    <Page>
      <Title>Update needed.</Title>
      <T v="body" color={color.ink2} style={styles.needed}>
        {`${who} runs a newer Vitals than this app can talk to. Update Vitals Remote to connect again.`}
      </T>
      <Actions view={view} />
      {nightlySupported && nightly._tag === "Available" ? <BigButton label={`Download Nightly build ${String(nightly.build)}`} onPress={() => void Linking.openURL(nightly.url)} /> : null}
      <Note>Nothing on your Mac changes.</Note>
    </Page>
  );
}

const styles = StyleSheet.create({
  needed: { paddingHorizontal: 20, paddingBottom: 18 },
  version: { paddingHorizontal: 20, paddingBottom: 14, gap: 2 },
  status: { flexDirection: "row", alignItems: "center", gap: 6 },
  statusTitle: { flexShrink: 1 },
  progress: { marginTop: 10, gap: 6 },
});
