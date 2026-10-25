import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { secondsLeft } from "@vitals/app/state/countdown.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { CHANNELS, LIVE_TOPICS } from "@vitals/app/features/chart/channels.ts";
import { useLiveTopics } from "@vitals/app/features/chart/hooks.ts";
import { isBroken, LinkState } from "@vitals/app/features/chart/LinkState.tsx";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useLatest, useLink, useNow, useSignal, useWord } from "@vitals/app/state/useVitals.ts";
import type { ConnectionState } from "@vitals/client-runtime";
import type { KeepAwakeState, LiveSample, MacInfo } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { type Channel, channels, Trace } from "@vitals/ui";
import { StyleSheet, View } from "react-native";

import { ALERT_TITLE, LINK_COLOR, TONE_COLOR, useMac } from "../lib/remote.ts";
import type { HomeStackParams } from "../navigation.ts";
import { AlertSheet } from "../sheets/AlertSheet.tsx";
import { PowerSheet } from "../sheets/PowerSheet.tsx";
import { color, Icon, Page, sheet, T, Tap } from "../ui/index.ts";

type Props = NativeStackScreenProps<HomeStackParams, "Home">;

const fansOf = (sample: LiveSample | null): boolean | null => (sample?.fans === undefined ? null : sample.fans.length > 0);
const batteryOf = (sample: LiveSample | null): boolean | null => (sample?.battery === undefined ? null : sample.battery !== null);

/** Waveform rows, in order. Fans hide on Macs without them. */
const WAVES: ReadonlyArray<{ readonly channel: Channel; readonly name: string }> = [
  { channel: "pulse", name: "CPU" },
  { channel: "press", name: "Memory" },
  { channel: "temp", name: "Temp" },
  { channel: "resp", name: "Fans" },
];

const MINIS: ReadonlyArray<{ readonly channel: Channel; readonly name: string }> = [
  { channel: "eeg", name: "GPU" },
  { channel: "drip", name: "Power" },
  { channel: "tele", name: "Net" },
  { channel: "oxy", name: "Batt" },
];

const keepAwakeLine = (state: KeepAwakeState): string => (state.until === null ? "keeping awake · until you stop it" : `keeping awake · until ${formatClock(state.until)}`);

function Header({ mac }: { readonly mac: MacInfo | null }) {
  const link = useLink();
  return (
    <View style={styles.head}>
      <View style={styles.who}>
        <T v="mono" color={color.ink2} numberOfLines={1}>
          {mac?.name ?? "Your Mac"}
        </T>
        <T v="mono" color={LINK_COLOR[link.tone]}>
          {link.tone === "live" || link.tone === "away" ? "●" : "○"}
        </T>
      </View>
      <Tap onPress={() => sheet.open(PowerSheet)} accessibilityRole="button" accessibilityLabel="Power" hitSlop={8} style={styles.power}>
        <Icon name="power" size={16} />
      </Tap>
    </View>
  );
}

function Meta({ mac }: { readonly mac: MacInfo | null }) {
  const remote = useRemote();
  const keepAwake = useStore(remote.events.keepAwake);
  const link = useLink();
  if (keepAwake?.active === true) {
    return (
      <T v="mono" color={color.orange} style={styles.meta}>
        {keepAwakeLine(keepAwake)}
      </T>
    );
  }
  return (
    <T v="mono" style={styles.meta}>
      {mac === null ? link.label : `${mac.chip} · macOS ${mac.os.replace(/^macOS\s*/i, "")} · ${link.label}`}
    </T>
  );
}

function Retry({ state }: { readonly state: Extract<ConnectionState, { readonly _tag: "Backoff" }> }) {
  const remote = useRemote();
  const now = useNow(1000);
  return (
    <StatusLine
      text={`○ Reconnecting · retry in ${secondsLeft(state.retryAt, now)}`}
      tint={color.orange}
      trailing="Retry"
      onPress={() => remote.connection.wake("manual")}
    />
  );
}

function StatusLine({ text, tint, trailing = "›", onPress }: { readonly text: string; readonly tint: string; readonly trailing?: string; readonly onPress?: () => void }) {
  const body = (
    <>
      <T v="mono" color={tint} numberOfLines={1} style={styles.statusText}>
        {text}
      </T>
      {onPress === undefined ? null : (
        <T v="mono" color={trailing === "›" ? tint : color.yellow}>
          {trailing}
        </T>
      )}
    </>
  );
  if (onPress === undefined) return <View style={styles.status}>{body}</View>;
  return (
    <Tap onPress={onPress} accessibilityRole="button" scale={0.99} style={styles.status}>
      {body}
    </Tap>
  );
}

/** One line for anything that needs attention. Problems collapse here; they never stack. */
function Attention() {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const alerts = useStore(remote.events.alerts);
  const calmed = useStore(remote.events.calmed);
  const signal = useSignal();
  if (state._tag === "Backoff") return <Retry state={state} />;
  if (!signal) return <StatusLine text="○ No signal from the Mac yet" tint={color.dim} />;
  // A critical alert outranks newer warnings.
  const first = alerts.find((alert) => alert.severity === "critical") ?? alerts[0];
  if (first !== undefined) {
    const more = alerts.length > 1 ? ` · +${String(alerts.length - 1)}` : "";
    return <StatusLine text={`▲ ${ALERT_TITLE[first.rule]} · ${first.summary}${more}`} tint={first.severity === "critical" ? color.red : color.orange} onPress={() => sheet.open(AlertSheet)} />;
  }
  if (calmed) return <StatusLine text="✓ Calmed" tint={color.dim} />;
  return null;
}

/** What a screen reader hears: the same reading the screen shows, or no signal when it shows `--`. */
const readingLabel = (name: string, reading: { readonly value: string; readonly unit: string }, signal: boolean) =>
  signal ? `${name}, ${reading.value} ${reading.unit}` : `${name}, no signal`;

function Wave({ channel, name, max, onOpen }: { readonly channel: Channel; readonly name: string; readonly max: number | null; readonly onOpen: (channel: Channel) => void }) {
  const remote = useRemote();
  const def = CHANNELS[channel];
  const reading = useLatest(def.reading);
  const signal = useSignal();
  const spec = channels[channel];
  const tint = signal ? spec.color : color.mute;
  return (
    <Tap onPress={() => onOpen(channel)} accessibilityRole="button" accessibilityLabel={readingLabel(name, reading, signal)} accessibilityHint={`Opens ${name} details`} scale={0.99} style={styles.wave}>
      <View style={styles.waveTop}>
        <T v="tag" color={tint}>{spec.tag === name.toUpperCase() ? spec.tag : `${spec.tag} · ${name.toUpperCase()}`}</T>
        <T v="value" color={signal ? color.ink : color.mute}>
          {signal ? reading.value : "--"}
          {signal && reading.unit !== "" ? <T v="mono">{` ${reading.unit}`}</T> : null}
        </T>
      </View>
      <Trace channel={channel} source={remote.live.series(def.series)} height={28} min={def.min} max={max ?? def.max} flat={!signal} />
    </Tap>
  );
}

function Mini({ channel, name, onOpen }: { readonly channel: Channel; readonly name: string; readonly onOpen: (channel: Channel) => void }) {
  const reading = useLatest(CHANNELS[channel].reading);
  const signal = useSignal();
  return (
    <Tap onPress={() => onOpen(channel)} accessibilityRole="button" accessibilityLabel={readingLabel(name, reading, signal)} layout={styles.miniSlot}>
      <T v="tag" color={channels[channel].color}>
        {name.toUpperCase()}
      </T>
      <T v="monoStrong" numberOfLines={1}>
        {signal ? `${reading.value}${reading.unit === "" ? "" : ` ${reading.unit}`}` : "--"}
      </T>
    </Tap>
  );
}

export function HomeScreen({ navigation }: Props) {
  useLiveTopics(LIVE_TOPICS);
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const mac = useMac();
  const word = useWord();
  const fans = useLatest(fansOf) ?? mac?.hasFans !== false;
  const battery = useLatest(batteryOf) ?? mac?.hasBattery !== false;
  if (isBroken(state)) return <LinkState state={state} who={mac?.name ?? "Your Mac"} />;
  const open = (channel: Channel) => navigation.navigate("Channel", { channel });
  const memoryMax = mac?.memoryBytes ?? null;
  return (
    <Page>
      <Header mac={mac} />
      <T v="word" color={TONE_COLOR[word.tone]} accessibilityRole="header" style={styles.word}>
        {word.word}
      </T>
      <Meta mac={mac} />
      <Attention />
      {WAVES.filter((wave) => wave.channel !== "resp" || fans).map((wave) => (
        <Wave key={wave.channel} channel={wave.channel} name={wave.name} max={wave.channel === "press" ? memoryMax : null} onOpen={open} />
      ))}
      <View style={styles.minis}>
        {MINIS.filter((mini) => mini.channel !== "oxy" || battery).map((mini) => (
          <Mini key={mini.channel} channel={mini.channel} name={mini.name} onOpen={open} />
        ))}
      </View>
    </Page>
  );
}

const styles = StyleSheet.create({
  head: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: 20, paddingTop: 4 },
  who: { flexDirection: "row", alignItems: "center", gap: 6, flex: 1 },
  power: { width: 40, height: 40, borderRadius: 20, borderWidth: 1, borderColor: color.line2, alignItems: "center", justifyContent: "center" },
  word: { paddingHorizontal: 20, paddingTop: 6 },
  meta: { paddingHorizontal: 20, paddingTop: 4, paddingBottom: 14 },
  status: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10, marginHorizontal: 20, marginBottom: 4, paddingVertical: 11, borderTopWidth: 1, borderBottomWidth: 1, borderColor: color.line2 },
  statusText: { flex: 1 },
  wave: { paddingHorizontal: 20, paddingTop: 11, paddingBottom: 6, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: color.line },
  waveTop: { flexDirection: "row", justifyContent: "space-between", alignItems: "baseline", marginBottom: 2 },
  minis: { flexDirection: "row", gap: 8, paddingHorizontal: 20, paddingTop: 12 },
  miniSlot: { flex: 1, gap: 2 },
});
