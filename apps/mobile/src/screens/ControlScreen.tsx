import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import type { KeepAwakeState } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { Slider } from "@vitals/ui";
import { useState } from "react";
import { StyleSheet, View } from "react-native";

import { send, useAccess } from "../lib/remote.ts";
import { PowerTiles } from "../sheets/PowerSheet.tsx";
import { ClipboardSheet, LinkSheet } from "../sheets/SendSheets.tsx";
import { color, Group, Label, Note, Page, Row, Segmented, type SegmentOption, sheet, Tile, TileGrid, Title, Toggle } from "../ui/index.ts";

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

export function ControlScreen() {
  const remote = useRemote();
  const access = useAccess();
  return (
    <Page>
      <Title>Control.</Title>
      <Label>Power</Label>
      <PowerTiles />
      <KeepAwake />
      <Sound />
      <Label>Send to Mac</Label>
      <TileGrid>
        <Tile icon="clipboard" label="Clipboard" disabled={!access.operate && !access.clipboard} onPress={() => sheet.open(ClipboardSheet)} />
        <Tile icon="link" label="Open link" disabled={!access.operate} onPress={() => sheet.open(LinkSheet)} />
        <Tile icon="ping" label="Find Mac" disabled={!access.operate} onPress={() => void send(remote, { _tag: "Locate" }, "Playing a sound on your Mac")} />
      </TileGrid>
      {access.operate ? null : <Note>This phone can only watch. Turn on control for it in Vitals on the Mac.</Note>}
    </Page>
  );
}

const styles = StyleSheet.create({
  slider: { marginHorizontal: 16, marginBottom: 10, backgroundColor: color.s2, borderRadius: 14, paddingHorizontal: 6, paddingVertical: 4 },
  off: { opacity: 0.4 },
});
