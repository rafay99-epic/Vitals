import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { type Line, type TerminalSession } from "@vitals/app/state/terminal.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { type TerminalId, type TerminalInfo, TERMINAL_LIMITS } from "@vitals/contracts";
import * as Clipboard from "expo-clipboard";
import * as LocalAuthentication from "expo-local-authentication";
import { type ComponentRef, memo, useEffect, useRef, useState } from "react";
import { type LayoutChangeEvent, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { useAccess } from "../lib/remote.ts";
import { BackBar, BigButton, color, Empty, font, Icon, Note, T, Tap, toast } from "../ui/index.ts";

const FONT_SIZE = 12;
const LINE_HEIGHT = 16;
const CHAR_WIDTH = FONT_SIZE * 0.6;
const UNLOCK_MS = 5 * 60 * 1000;
const SENTINEL = " ";

let unlockedAt = 0;

const KEYS: ReadonlyArray<{ readonly label: string; readonly data: string | null }> = [
  { label: "esc", data: "\u001b" },
  { label: "tab", data: "\t" },
  { label: "ctrl", data: null },
  { label: "↑", data: "\u001b[A" },
  { label: "↓", data: "\u001b[B" },
  { label: "←", data: "\u001b[D" },
  { label: "→", data: "\u001b[C" },
  { label: "^C", data: "\u0003" },
  { label: "|", data: "|" },
  { label: "~", data: "~" },
  { label: "/", data: "/" },
  { label: "-", data: "-" },
];

const control = (text: string): string => {
  const code = text.toUpperCase().charCodeAt(0);
  return code >= 64 && code <= 95 ? String.fromCharCode(code - 64) : text;
};

const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

const TermLine = memo(function TermLine({ line }: { readonly line: Line }) {
  return (
    <Text style={styles.line} numberOfLines={1}>
      {line.runs.map((run) => (
        <Text
          key={run.col}
          style={{
            color: run.fg ?? color.ink2,
            backgroundColor: run.bg ?? undefined,
            fontFamily: run.bold ? font.monoMedium : font.mono,
            opacity: run.dim ? 0.6 : 1,
            fontStyle: run.italic ? "italic" : "normal",
            textDecorationLine: run.underline ? "underline" : "none",
          }}
        >
          {run.text}
        </Text>
      ))}
    </Text>
  );
});

function Screen({ session }: { readonly session: TerminalSession }) {
  const frame = useStore(session.frame);
  return (
    <View style={styles.grid} accessibilityRole="text" accessibilityLabel={frame.lines.map((line) => line.runs.map((run) => run.text).join("")).join("\n")}>
      {frame.lines.map((line) => (
        <TermLine key={line.key} line={line} />
      ))}
      {frame.exited ? <T v="mono" color={color.dim} style={styles.exited}>{`Ended${frame.exitCode === null ? "" : ` · code ${String(frame.exitCode)}`}`}</T> : null}
    </View>
  );
}

function Keys({ onKey, ctrl, onCtrl }: { readonly onKey: (data: string) => void; readonly ctrl: boolean; readonly onCtrl: () => void }) {
  const paste = () =>
    void Clipboard.getStringAsync().then((text) => {
      if (text.length > 0) onKey(text.replace(/\r?\n/g, "\r").slice(0, TERMINAL_LIMITS.write));
    });
  return (
    <ScrollView horizontal keyboardShouldPersistTaps="always" showsHorizontalScrollIndicator={false} style={styles.keys} contentContainerStyle={styles.keysRow}>
      {KEYS.map((key) => (
        <Pressable
          key={key.label}
          onPress={() => (key.data === null ? onCtrl() : onKey(key.data))}
          accessibilityRole="button"
          accessibilityLabel={key.label}
          style={[styles.key, key.data === null && ctrl ? styles.keyOn : null]}
        >
          <Text style={[styles.keyText, key.label === "^C" ? { color: color.red } : null, key.data === null && ctrl ? { color: color.bg } : null]}>{key.label}</Text>
        </Pressable>
      ))}
      <Pressable onPress={paste} accessibilityRole="button" accessibilityLabel="Paste" style={styles.key}>
        <Text style={styles.keyText}>paste</Text>
      </Pressable>
    </ScrollView>
  );
}

function Session({ info }: { readonly info: TerminalInfo }) {
  const remote = useRemote();
  const [size, setSize] = useState<{ readonly cols: number; readonly rows: number } | null>(null);
  const [ctrl, setCtrl] = useState(false);
  const input = useRef<ComponentRef<typeof TextInput>>(null);
  const session = size === null ? null : remote.terminals.session(info.id, size);

  useEffect(() => {
    if (session === null) return;
    session.attach();
    return () => session.detach();
  }, [session]);

  useEffect(() => {
    if (session !== null && size !== null) session.resize(size);
  }, [session, size]);

  const measure = (event: LayoutChangeEvent) => {
    const { width, height } = event.nativeEvent.layout;
    const cols = clamp(Math.floor((width - 16) / CHAR_WIDTH), TERMINAL_LIMITS.cols.min, TERMINAL_LIMITS.cols.max);
    const rows = clamp(Math.floor((height - 8) / LINE_HEIGHT), TERMINAL_LIMITS.rows.min, TERMINAL_LIMITS.rows.max);
    setSize((current) => (current?.cols === cols && current.rows === rows ? current : { cols, rows }));
  };

  const send = (data: string) => {
    if (ctrl && data.length === 1) {
      session?.input(control(data));
      setCtrl(false);
      return;
    }
    session?.input(data);
  };

  const typed = (text: string) => {
    if (text.length < SENTINEL.length) send("\u007f");
    else if (text.length > SENTINEL.length) send(text.slice(SENTINEL.length));
  };

  return (
    <View style={styles.session}>
      <Pressable style={styles.surface} onLayout={measure} onPress={() => input.current?.focus()} accessibilityHint="Opens the keyboard">
        {session === null ? null : <Screen session={session} />}
      </Pressable>
      <TextInput
        ref={input}
        value={SENTINEL}
        onChangeText={typed}
        onSubmitEditing={() => send("\r")}
        submitBehavior="submit"
        autoFocus
        autoCorrect={false}
        autoCapitalize="none"
        autoComplete="off"
        spellCheck={false}
        keyboardType="visible-password"
        caretHidden
        style={styles.hiddenInput}
        accessibilityLabel="Type into the terminal"
      />
      <Keys onKey={send} ctrl={ctrl} onCtrl={() => setCtrl((on) => !on)} />
    </View>
  );
}

function Locked({ onUnlock }: { readonly onUnlock: () => void }) {
  const unlock = () =>
    void LocalAuthentication.authenticateAsync({ promptMessage: "Unlock Terminal", disableDeviceFallback: false }).then((result) => {
      if (!result.success) return;
      unlockedAt = Date.now();
      onUnlock();
    });
  useEffect(unlock, []);
  return (
    <View style={styles.center}>
      <View style={styles.lockRing}>
        <Icon name="lock" size={26} color={color.yellow} />
      </View>
      <T v="strong">Unlock Terminal</T>
      <T v="small" style={styles.centerText}>
        Asked every time you come back after 5 minutes away.
      </T>
      <BigButton label="Unlock" onPress={unlock} />
    </View>
  );
}

export function TerminalScreen() {
  const remote = useRemote();
  const access = useAccess();
  const insets = useSafeAreaInsets();
  const sessions = useStore(remote.terminals.sessions);
  const [unlocked, setUnlocked] = useState(() => Date.now() - unlockedAt < UNLOCK_MS);
  const [active, setActive] = useState<TerminalId | null>(null);
  const state = useStore(remote.connection.state);
  const supported = state._tag === "Ready" && state.hello.terminal === true;

  useEffect(() => {
    if (unlocked && access.terminal && supported) void remote.terminals.refresh();
  }, [remote, unlocked, access.terminal, supported]);

  useEffect(() => () => {
    unlockedAt = Date.now();
  }, []);

  const current = sessions.find((session) => session.id === active) ?? sessions[0] ?? null;

  const start = () =>
    void remote.terminals.start({ cols: 80, rows: 24 }).then((result) => {
      if (typeof result === "string") toast.show(result, { tone: "bad" });
      else setActive(result.id);
    });

  const body = !supported ? (
    <Empty title="Update Vitals on your Mac" detail="This Mac doesn't have Terminal yet." />
  ) : !access.terminal ? (
    <View style={styles.center}>
      <T v="strong">Terminal is off for this phone</T>
      <Note>It runs commands on your Mac as you. Turn it on in Vitals on the Mac: Remote › this phone › Terminal.</Note>
    </View>
  ) : !unlocked ? (
    <Locked onUnlock={() => setUnlocked(true)} />
  ) : current === null ? (
    <View style={styles.center}>
      <T v="strong">No terminals open</T>
      <BigButton label="Open a terminal" onPress={start} />
    </View>
  ) : (
    <Session key={current.id} info={current} />
  );

  return (
    <View style={[styles.screen, { paddingTop: insets.top + 6, paddingBottom: insets.bottom }]}>
      <View style={styles.bar}>
        <BackBar parent="Control" />
        {unlocked && access.terminal ? (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
            {sessions.map((session, index) => (
              <Tap key={session.id} onPress={() => setActive(session.id)} onLongPress={() => void remote.terminals.end(session.id)} accessibilityRole="button" accessibilityLabel={`Terminal ${String(index + 1)}`} accessibilityHint="Long press to end it" style={[styles.chip, session.id === current?.id ? styles.chipOn : null]}>
                <T v="mono" color={session.id === current?.id ? color.bg : color.dim}>{`${session.title} ${String(index + 1)}`}</T>
              </Tap>
            ))}
            <Tap onPress={start} accessibilityRole="button" accessibilityLabel="New terminal" style={styles.chip}>
              <Icon name="plus" size={14} color={color.dim} />
            </Tap>
          </ScrollView>
        ) : null}
      </View>
      {body}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: color.bg },
  bar: { flexDirection: "row", alignItems: "center", gap: 8, paddingRight: 12, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: color.line, paddingBottom: 8 },
  chips: { gap: 6, alignItems: "center" },
  chip: { borderWidth: 1, borderColor: color.line2, borderRadius: 10, paddingHorizontal: 9, paddingVertical: 5, alignItems: "center", justifyContent: "center" },
  chipOn: { backgroundColor: color.yellow, borderColor: color.yellow },
  session: { flex: 1 },
  surface: { flex: 1, paddingHorizontal: 8, paddingTop: 6, overflow: "hidden" },
  grid: { flex: 1 },
  line: { fontFamily: font.mono, fontSize: FONT_SIZE, lineHeight: LINE_HEIGHT, color: color.ink2, includeFontPadding: false },
  exited: { paddingTop: 6 },
  hiddenInput: { position: "absolute", width: 1, height: 1, opacity: 0 },
  keys: { flexGrow: 0, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: color.line2, backgroundColor: color.s1 },
  keysRow: { gap: 6, paddingHorizontal: 8, paddingVertical: 6 },
  key: { minWidth: 36, height: 34, borderRadius: 8, backgroundColor: color.s3, paddingHorizontal: 10, alignItems: "center", justifyContent: "center" },
  keyOn: { backgroundColor: color.yellow },
  keyText: { fontFamily: font.mono, fontSize: 12, color: color.ink2 },
  center: { flex: 1, alignItems: "center", justifyContent: "center", gap: 12, paddingHorizontal: 28 },
  centerText: { textAlign: "center" },
  lockRing: { width: 64, height: 64, borderRadius: 32, borderWidth: 1.5, borderColor: color.yellow, alignItems: "center", justifyContent: "center" },
});
