import { useFocusEffect } from "@react-navigation/native";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { RULES } from "@vitals/app/features/alarms/rules.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { bytes } from "@vitals/app/state/vitals.ts";
import type { Alert, GuardSettings, GuardState, MemoryPressure, ThermalState } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { useCallback, useRef, useState } from "react";
import { StyleSheet, View } from "react-native";

import { ALERT_TITLE, send, useAccess } from "../lib/remote.ts";
import { calm } from "../sheets/AlertSheet.tsx";
import { BigButton, Card, color, Empty, Group, Label, Note, Page, Row, Stats, T, Tap, Title, toast, Toggle } from "../ui/index.ts";

type Edit = (settings: GuardSettings) => GuardSettings;

const PRESSURE: Record<MemoryPressure, { readonly word: string; readonly color: string }> = {
  normal: { word: "Normal", color: color.ink },
  warning: { word: "Tight", color: color.orange },
  critical: { word: "Full", color: color.red },
};

const HEAT: Record<ThermalState, { readonly word: string; readonly color: string }> = {
  nominal: { word: "Cool", color: color.ink },
  fair: { word: "Warm", color: color.ink },
  serious: { word: "Hot", color: color.orange },
  critical: { word: "Too hot", color: color.red },
};

function AlertCard({ alert, calmed, canAct }: { readonly alert: Alert; readonly calmed: boolean; readonly canAct: boolean }) {
  const remote = useRemote();
  const critical = alert.severity === "critical";
  return (
    <Card tone={critical ? "bad" : "warn"}>
      <T v="strong" color={critical ? color.red : color.orange} style={styles.cardTitle}>
        {`▲ ${ALERT_TITLE[alert.rule]}`}
      </T>
      <T v="body" color={color.ink2}>{`${alert.summary}. Since ${formatClock(alert.raisedAt)}.`}</T>
      <T v="small" style={styles.cardPlan}>Calming lowers the priority of what is crowding the Mac right now. Nothing gets closed.</T>
      {canAct ? (
        <View style={styles.cardButton}>
          <BigButton label={calmed ? "Calm again" : "Calm it down"} onPress={() => calm(remote, alert)} />
        </View>
      ) : null}
    </Card>
  );
}

function Calmed() {
  const remote = useRemote();
  const access = useAccess();
  return (
    <Card tone="quiet">
      <T v="strong" color={color.ink2} style={styles.cardTitle}>
        ✓ Calmed
      </T>
      <View style={styles.calmedRow}>
        <T v="small" style={styles.calmedText}>
          Agents run at low priority and idle emulators are paused.
        </T>
        {access.operate ? (
          <Tap onPress={() => void send(remote, { _tag: "UndoCalm" }, "Back to normal priority")} accessibilityRole="button" hitSlop={10}>
            <T v="strong" color={color.yellow}>
              Undo
            </T>
          </Tap>
        ) : null}
      </View>
    </Card>
  );
}

function Rules({ guard, locked, onChange }: { readonly guard: GuardState | null; readonly locked: boolean; readonly onChange: (edit: Edit) => void }) {
  if (guard === null) return <Empty title="Reading the rules." detail="They load once the Mac is connected." />;
  const settings = guard.settings;
  return (
    <Group>
      <Row
        first
        label="Watch this Mac"
        detail={settings.enabled ? "Alerts are on" : "Off: no alerts, no calming"}
        control={<Toggle value={settings.enabled} label="Watch this Mac" disabled={locked} onChange={(enabled) => onChange((latest) => ({ ...latest, enabled }))} />}
      />
      {settings.rules.map((rule) => (
        <Row
          key={rule.kind}
          label={ALERT_TITLE[rule.kind]}
          detail={RULES[rule.kind].detail(rule)}
          control={
            <Toggle
              value={rule.enabled}
              label={ALERT_TITLE[rule.kind]}
              disabled={locked || !settings.enabled}
              onChange={(enabled) => onChange((latest) => ({ ...latest, rules: latest.rules.map((item) => (item.kind === rule.kind ? { ...item, enabled } : item)) }))}
            />
          }
        />
      ))}
    </Group>
  );
}

function Earlier() {
  const entries = useStore(useRemote().events.log).filter((entry) => entry.clearedAt !== null);
  if (entries.length === 0) return <Note>Nothing yet. Alerts that clear while the app is open show here.</Note>;
  return (
    <Group>
      {entries.slice(0, 8).map((entry, index) => (
        <Row key={entry.id} first={index === 0} label={entry.summary} value={`${formatClock(entry.raisedAt)} to ${formatClock(entry.clearedAt ?? entry.raisedAt)}`} />
      ))}
    </Group>
  );
}

export function AlertsScreen() {
  const remote = useRemote();
  const access = useAccess();
  const events = useStore(remote.events.alerts);
  const calmedRecently = useStore(remote.events.calmed);
  const ready = useStore(remote.connection.state)._tag === "Ready";
  const [watched, setWatched] = useState<GuardState | null>(null);
  // Edits wait for a snapshot taken since this screen last gained focus, so they never build on stale rules.
  const [fresh, setFresh] = useState(false);
  const confirmed = useRef<GuardSettings | null>(null);
  const queue = useRef<Promise<void> | null>(null);
  const guard = ready ? watched : null;

  const receive = useCallback((next: GuardState) => {
    confirmed.current = next.settings;
    setWatched(next);
    setFresh(true);
  }, []);
  useFocusEffect(
    useCallback(() => {
      setFresh(false);
      return remote.connection.watch((client) => client["guard.watch"]({}), receive);
    }, [remote, receive]),
  );

  const revert = () => setWatched((current) => (current === null || confirmed.current === null ? current : { ...current, settings: confirmed.current }));
  const save = async (edit: Edit) => {
    const base = confirmed.current;
    if (base === null) return;
    const result = await remote.connection.call((client) => client["guard.update"](edit(base)));
    if (!result.ok) {
      toast.show(result.error.message, { tone: "bad" });
      revert();
      return;
    }
    confirmed.current = result.value;
    setWatched((current) => (current === null ? current : { ...current, settings: result.value }));
  };
  // Shows the change at once so a quick second tap toggles back, then saves in order against what the Mac confirmed.
  const update = (edit: Edit) => {
    setWatched((current) => (current === null ? current : { ...current, settings: edit(current.settings) }));
    queue.current = (queue.current ?? Promise.resolve()).then(() => save(edit)).catch(() => {
      toast.show("The rule did not change. Try again.", { tone: "bad" });
      revert();
    });
  };

  const open = guard?.active ?? events;
  const calmed = guard?.calmApplied === true || calmedRecently;
  const swap = bytes(guard?.swapUsedBytes);

  return (
    <Page>
      <Title>Alerts.</Title>
      {open.map((alert) => (
        <AlertCard key={alert.id} alert={alert} calmed={calmed} canAct={access.operate} />
      ))}
      {guard?.calmApplied === true ? <Calmed /> : null}
      {open.length === 0 && guard?.calmApplied !== true ? (
        <Card tone="quiet">
          <T v="strong" color={color.ink2}>
            No alerts right now.
          </T>
          <T v="small">Vitals tells you here, and with a notification, when your Mac needs a hand.</T>
        </Card>
      ) : null}
      <Stats
        items={[
          { label: "Memory", value: guard === null ? "--" : PRESSURE[guard.pressure].word, color: guard === null ? color.ink : PRESSURE[guard.pressure].color },
          { label: "Swap", value: swap.unit === "" ? swap.value : `${swap.value} ${swap.unit}` },
          { label: "Heat", value: guard === null ? "--" : HEAT[guard.thermal].word, color: guard === null ? color.ink : HEAT[guard.thermal].color },
        ]}
      />
      <Label>Tell me when</Label>
      <Rules guard={guard} locked={!access.operate || !fresh} onChange={update} />
      <Label>Earlier</Label>
      <Earlier />
    </Page>
  );
}

const styles = StyleSheet.create({
  cardTitle: { fontSize: 16, marginBottom: 6 },
  cardPlan: { marginTop: 6 },
  cardButton: { marginTop: 14, marginHorizontal: -16, marginBottom: -8 },
  calmedRow: { flexDirection: "row", alignItems: "center", gap: 12 },
  calmedText: { flex: 1 },
});
