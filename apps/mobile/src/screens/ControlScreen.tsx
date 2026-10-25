import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipAge } from "@vitals/app/features/clips/format.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import type { KeepAwakeState } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { Slider } from "@vitals/ui";
import { useState } from "react";
import { StyleSheet, View } from "react-native";

import { copyToPhone } from "../lib/clips.ts";
import { send, useAccess } from "../lib/remote.ts";
import type { ControlStackParams } from "../navigation.ts";
import { PowerTiles } from "../sheets/PowerSheet.tsx";
import { LinkSheet } from "../sheets/SendSheets.tsx";
import { color, Group, Label, Note, Page, Row, Segmented, type SegmentOption, sheet, T, Tap, Tile, TileGrid, Title, toast, Toggle } from "../ui/index.ts";
import { ClipRow } from "./ClipboardScreen.tsx";

type Awake = "off" | "1h" | "4h" | "always";

const HOUR = 3_600_000;

const AWAKE_OPTIONS: ReadonlyArray<SegmentOption<Awake>> = [
  { value: "off", label: "Off" },
  { value: "1h", label: "1 h" },
  { value: "4h", label: "4 h" },
  { value: "always", label: "Always" },
];

/** Which option matches what the Mac reports. Timed stays fall back to the nearest choice. */
const awakeOf = (state: KeepAwakeState | null, chosen: Awake | null): Awake => {
  if (state?.active !== true) return "off";
  if (state.until === null) return "always";
  if (chosen === "1h" || chosen === "4h") return chosen;
  return state.until - Date.now() <= 2.5 * HOUR ? "1h" : "4h";
};

const awakeLine = (state: KeepAwakeState | null): string | undefined => {
  if (state?.active !== true) return "sleeps on its own";
  return state.until === null ? "until you stop it" : `until ${formatClock(state.until)}`;
};

function KeepAwake() {
  const remote = useRemote();
  const access = useAccess();
  const state = useStore(remote.events.keepAwake);
  const [chosen, setChosen] = useState<Awake | null>(null);
  // Remember the pick only once the Mac accepts it, so a failed request can't show a state the Mac isn't in.
  const choose = (next: Awake) => {
    if (next === "off") {
      setChosen(null);
      return void send(remote, { _tag: "AllowSleep" }, "Your Mac can sleep again");
    }
    const until = next === "always" ? null : Date.now() + (next === "1h" ? HOUR : 4 * HOUR);
    const done = next === "always" ? "Keeping your Mac awake until you stop it" : `Keeping your Mac awake for ${next === "1h" ? "1 hour" : "4 hours"}`;
    void send(remote, { _tag: "KeepAwake", until, display: false, whileProcess: null }, done).then((ok) => ok && setChosen(next));
  };
  return (
    <>
      <Label right={awakeLine(state)}>Keep awake</Label>
      <Segmented options={AWAKE_OPTIONS} value={awakeOf(state, chosen)} onChange={choose} disabled={!access.operate} />
    </>
  );
}

function Sound() {
  const remote = useRemote();
  const access = useAccess();
  const [volume, setVolume] = useState(0.5);
  const [muted, setMuted] = useState(false);
  return (
    <>
      <Label right="last set from this phone">Sound</Label>
      <View style={[styles.slider, access.operate ? null : styles.off]}>
        <Slider
          value={volume}
          disabled={!access.operate}
          accessibilityLabel="Mac volume"
          format={(level) => String(Math.round(level * 100))}
          onCommit={(level) => {
            setVolume(level);
            void send(remote, { _tag: "SetVolume", level }, null);
          }}
        />
      </View>
      <Group>
        <Row
          first
          label="Mute"
          control={
            <Toggle
              value={muted}
              label="Mute the Mac"
              disabled={!access.operate}
              onChange={(next) => {
                setMuted(next);
                void send(remote, { _tag: "SetMuted", muted: next }, next ? "Mac muted" : "Mac unmuted");
              }}
            />
          }
        />
      </Group>
    </>
  );
}

/** The Mac's latest copy, one tap from the phone clipboard, then the clipboard and send tiles. */
function Clipboard() {
  const remote = useRemote();
  const access = useAccess();
  const navigation = useNavigation<NativeStackNavigationProp<ControlStackParams>>();
  const now = useNow(30_000);
  const clips = useStore(remote.clips.clips);
  const enabled = useStore(remote.clips.enabled);
  const supported = useStore(remote.clips.supported);
  const showing = access.clipboard && supported !== false && enabled === true;
  const latest = showing ? clips.find((clip) => clip.deviceId === null) : undefined;
  const open = () => navigation.navigate("Clipboard");
  const copy = latest !== undefined && (latest.kind === "text" || latest.kind === "link" || latest.kind === "image") ? latest : null;
  return (
    <>
      <Label right={showing ? `${String(clips.length)} on the Mac` : undefined}>Clipboard</Label>
      {showing && latest === undefined ? <Note>Nothing copied on the Mac yet.</Note> : null}
      {latest === undefined ? null : (
        <View style={styles.latest}>
          <ClipRow
            clip={latest}
            meta={`Mac copied · ${clipAge(latest.at, now)}`}
            onPress={open}
            action={
              copy === null ? undefined : (
                <Tap onPress={() => void copyToPhone(remote, copy).then((ok) => ok && toast.show("Copied to this phone"))} accessibilityRole="button" accessibilityLabel="Copy to this phone" hitSlop={10}>
                  <T v="strong" color={color.yellow}>
                    Copy
                  </T>
                </Tap>
              )
            }
          />
        </View>
      )}
      <TileGrid>
        <Tile icon="clipboard" label="Clipboard" disabled={!access.operate && !access.clipboard} onPress={open} />
        <Tile icon="link" label="Open link" disabled={!access.operate} onPress={() => sheet.open(LinkSheet)} />
        <Tile icon="ping" label="Find Mac" disabled={!access.operate} onPress={() => void send(remote, { _tag: "Locate" }, "Playing a sound on your Mac")} />
      </TileGrid>
    </>
  );
}

export function ControlScreen() {
  const access = useAccess();
  return (
    <Page>
      <Title>Control.</Title>
      <Label>Power</Label>
      <PowerTiles />
      <KeepAwake />
      <Sound />
      <Clipboard />
      {access.operate ? null : <Note>This phone can only watch. Turn on control for it in Vitals on the Mac.</Note>}
    </Page>
  );
}

const styles = StyleSheet.create({
  slider: { marginHorizontal: 16, marginBottom: 10, backgroundColor: color.s2, borderRadius: 14, paddingHorizontal: 6, paddingVertical: 4 },
  off: { opacity: 0.4 },
  latest: { marginHorizontal: 16, marginBottom: 10, backgroundColor: color.s2, borderRadius: 16, paddingVertical: 4, overflow: "hidden" },
});
