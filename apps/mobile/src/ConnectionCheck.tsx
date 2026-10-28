import { sessions } from "@vitals/app/connection/session.ts";
import { useSession } from "@vitals/app/connection/useRemote.ts";
import { journal } from "@vitals/app/state/journal.ts";
import { CLIENT_VERSION } from "@vitals/app/state/remote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { Store } from "@vitals/client-runtime";
import { useEffect } from "react";
import { Linking, Modal, Share, StyleSheet, View } from "react-native";

import { connectionCheck, runCheck } from "./lib/check.ts";
import { type CheckRun, fixFor, LABELS, type Mark, reportOf } from "./lib/checkModel.ts";
import { BigButton, Card, color, Group, Label, Note, Page, Row, space, T, Tap, Title } from "./ui/index.ts";

const open = new Store(false);

/** Opens the connection check, which runs at once. */
export const openCheck = (): void => open.set(true);

const MARKS: Record<Mark, { readonly glyph: string; readonly tint: string; readonly said: string }> = {
  ok: { glyph: "✓", tint: color.green, said: "passed" },
  warn: { glyph: "!", tint: color.orange, said: "passed with a warning" },
  failed: { glyph: "✕", tint: color.red, said: "failed" },
  running: { glyph: "…", tint: color.dim, said: "running" },
  waiting: { glyph: "–", tint: color.mute, said: "waiting" },
  skipped: { glyph: "–", tint: color.mute, said: "not run" },
};

const EARLIER = 12;

const time = (at: number): string => new Date(at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

const ranFor = (run: CheckRun): string =>
  run.finishedAt === null ? "Checking" : `Ran at ${time(run.startedAt)} · ${((run.finishedAt - run.startedAt) / 1000).toFixed(1)} s`;

function Fix({ run }: { readonly run: CheckRun }) {
  const session = useSession();
  const fix = fixFor(run);
  if (run.finishedAt === null) return null;
  if (fix === null) {
    return (
      <Card tone="quiet">
        <T v="medium">Every check passed.</T>
      </Card>
    );
  }
  return (
    <>
      <Card tone="bad">
        <T v="medium">{fix.title}</T>
        <T v="small" style={styles.fixDetail}>
          {fix.detail}
        </T>
      </Card>
      {fix.action === "settings" ? <BigButton ghost label="Open phone settings" onPress={() => void Linking.openSettings()} /> : null}
      {fix.action === "pair" && session.status === "paired" ? (
        <BigButton
          ghost
          label="Pair again"
          onPress={() => {
            open.set(false);
            void sessions.forget();
          }}
        />
      ) : null}
    </>
  );
}

/** The connection check from Settings › Connection and from "Why?" under a pairing error. */
export function ConnectionCheck() {
  const visible = useStore(open);
  const run = useStore(connectionCheck);
  const lines = useStore(journal);

  useEffect(() => {
    if (visible) void runCheck();
  }, [visible]);

  if (!visible) return null;
  const share = () => {
    if (run !== null) void Share.share({ message: reportOf(run, CLIENT_VERSION, journal.get()) });
  };
  return (
    <Modal animationType="slide" statusBarTranslucent navigationBarTranslucent onRequestClose={() => open.set(false)}>
      <View style={styles.screen}>
        <Page>
          <Tap onPress={() => open.set(false)} accessibilityRole="button" hitSlop={12} style={styles.done}>
            <T v="medium" color={color.yellow}>
              Done
            </T>
          </Tap>
          <Title>Connection check.</Title>
          <Note>{run === null ? "Checking" : ranFor(run)}</Note>
          {run === null ? null : (
            <Group>
              {run.steps.map((step, index) => {
                const mark = MARKS[step.mark];
                return (
                  <View key={step.id} accessible accessibilityLabel={`${LABELS[step.id]}, ${mark.said}${step.detail === null ? "" : `. ${step.detail}`}`}>
                    <Row first={index === 0} label={LABELS[step.id]} detail={step.detail ?? undefined} value={mark.glyph} valueColor={mark.tint} />
                  </View>
                );
              })}
            </Group>
          )}
          {run === null ? null : <Fix run={run} />}
          <BigButton label="Check again" disabled={run !== null && run.finishedAt === null} onPress={() => void runCheck()} />
          <BigButton ghost label="Share report" disabled={run === null} onPress={share} />
          <Label right={`${String(Math.min(EARLIER, lines.length))} of ${String(lines.length)}`}>Earlier</Label>
          <View style={styles.log}>
            {lines
              .slice(-EARLIER)
              .toReversed()
              .map((entry) => (
                <View key={`${String(entry.at)}${entry.kind}${entry.text}`} style={styles.entry}>
                  <T v="mono" style={styles.at}>
                    {time(entry.at)}
                  </T>
                  <T v="mono" color={color.ink2} style={styles.text}>
                    {`${entry.kind} ${entry.text}`}
                  </T>
                </View>
              ))}
          </View>
        </Page>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: color.bg },
  done: { alignSelf: "flex-start", paddingHorizontal: space.edge, paddingVertical: 8 },
  fixDetail: { marginTop: 4 },
  log: { paddingHorizontal: space.gutter },
  entry: { flexDirection: "row", gap: 10, paddingVertical: 6, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: color.line },
  at: { width: 44 },
  text: { flex: 1 },
});
