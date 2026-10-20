import { useFocusEffect } from "@react-navigation/native";
import type { Alert, GuardRule, GuardSettings, GuardState } from "@vitals/contracts";
import { formatBytes, formatClock } from "@vitals/shared";
import { BeatSwitch, Columns, EmptyState, HoldRow, KeyValueGrid, Row, Screen, Section, type Tone, useWide } from "@vitals/ui";
import { useCallback, useState } from "react";

import { AlertBanner } from "../../components/AlertBanner.tsx";
import { TabHeader } from "../../components/TabHeader.tsx";
import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";
import { useScopes } from "../../state/useScopes.ts";
import { useStore } from "../../state/useStore.ts";
import { bytes } from "../../state/vitals.ts";
import { WARD_NAMES } from "../../state/wards.ts";
import { PRESSURE_TONE, RULES, THERMAL_TONE } from "./rules.ts";

const SEVERITY_TONE: Record<Alert["severity"], Tone> = { warning: "alarmMedium", critical: "alarmHigh" };

const capitalize = (word: string): string => `${word.charAt(0).toUpperCase()}${word.slice(1)}`;

const guardMeta = (guard: GuardState | null): string => {
  if (guard === null) return "Pressure Guard · reading the Mac";
  if (!guard.settings.enabled) return "Pressure Guard · off";
  const on = guard.settings.rules.filter((rule) => rule.enabled).length;
  return `Pressure Guard · watching ${String(on)} of ${String(guard.settings.rules.length)} rules`;
};

function Header({ alerts, guard }: { readonly alerts: ReadonlyArray<Alert>; readonly guard: GuardState | null }) {
  const meta = guardMeta(guard);
  if (alerts.length > 0) return <TabHeader meta={meta} />;
  if (guard?.calmApplied === true) return <TabHeader title="Calmed." titleTone="pulse" meta={meta} />;
  return <TabHeader title="Alarms." meta={meta} />;
}

function Readouts({ guard }: { readonly guard: GuardState | null }) {
  const swap = bytes(guard?.swapUsedBytes);
  return (
    <KeyValueGrid
      items={[
        { key: "Pressure", value: guard === null ? "--" : capitalize(guard.pressure), tone: guard === null ? "ink" : PRESSURE_TONE[guard.pressure] },
        { key: "Swap", value: swap.value, unit: swap.unit },
        { key: "Thermal", value: guard === null ? "--" : capitalize(guard.thermal), tone: guard === null ? "ink" : THERMAL_TONE[guard.thermal] },
      ]}
    />
  );
}

function OpenAlerts({ alerts, locked }: { readonly alerts: ReadonlyArray<Alert>; readonly locked: boolean }) {
  return alerts.map((alert) => <AlertBanner key={alert.id} alert={alert} locked={locked} />);
}

function Calm({ guard, alerts, locked }: { readonly guard: GuardState | null; readonly alerts: ReadonlyArray<Alert>; readonly locked: boolean }) {
  const remote = useRemote();
  const calmed = guard?.calmApplied === true;
  return (
    <Section title="Calm">
      <HoldRow
        label="Calm"
        hint={"lower agent priority\npause idle emulators"}
        locked={locked}
        onStart={haptics.soft}
        onCommit={() => {
          haptics.success();
          void remote.run({ _tag: "CalmDown", alertId: alerts[0]?.id ?? null });
        }}
      />
      <Row label="Undo calm" detail={calmed ? "restores every calmed process" : "nothing is calmed"} locked={locked || !calmed} onPress={() => void remote.run({ _tag: "UndoCalm" })} />
    </Section>
  );
}

function Rules({ guard, locked, onChange }: { readonly guard: GuardState | null; readonly locked: boolean; readonly onChange: (settings: GuardSettings) => void }) {
  if (guard === null) return <EmptyState title="Reading the rules." detail="Pressure Guard answers once the Mac is connected." />;
  const settings = guard.settings;
  const toggle = (rule: GuardRule, enabled: boolean) => {
    haptics.light();
    onChange({ ...settings, rules: settings.rules.map((item) => (item.kind === rule.kind ? { ...item, enabled } : item)) });
  };
  return (
    <Section title="Rules" trailing="fire after the hold">
      <Row
        label="Pressure Guard"
        detail={settings.enabled ? "watching this Mac" : "off: no alarms, no calming"}
        locked={locked}
        trailing={<BeatSwitch value={settings.enabled} disabled={locked} accessibilityLabel="Pressure Guard" onChange={(enabled) => onChange({ ...settings, enabled })} />}
      />
      {settings.rules.map((rule) => (
        <Row
          key={rule.kind}
          label={RULES[rule.kind].title}
          detail={RULES[rule.kind].detail(rule)}
          locked={locked || !settings.enabled}
          trailing={
            <BeatSwitch
              value={rule.enabled}
              disabled={locked || !settings.enabled}
              accessibilityLabel={`${RULES[rule.kind].title}, alarm rule`}
              onChange={(enabled) => toggle(rule, enabled)}
            />
          }
        />
      ))}
    </Section>
  );
}

function Wards({ guard }: { readonly guard: GuardState | null }) {
  const groups = (guard?.groups ?? []).filter((group) => group.count > 0 && group.group !== "protected");
  return (
    <Section title="Wards a calm touches">
      {groups.length === 0 ? <EmptyState title="Quiet wards." detail="No agents, emulators or dev servers are running." /> : null}
      {groups.map((group) => (
        <Row key={group.group} label={WARD_NAMES[group.group]} value={`${String(group.count)} · ${group.cpuPercent.toFixed(0)}% · ${formatBytes(group.memoryBytes)}`} />
      ))}
    </Section>
  );
}

function AlarmLog() {
  const remote = useRemote();
  const entries = useStore(remote.events.log);
  return (
    <Section title="Alarm log" trailing="this session">
      {entries.length === 0 ? <EmptyState title="No alarms." detail="Alarms raised while Vitals is open on this device show here." /> : null}
      {entries.map((entry) => (
        <Row
          key={entry.id}
          label={entry.summary}
          detail={entry.clearedAt === null ? `${formatClock(entry.raisedAt)} · open` : `${formatClock(entry.raisedAt)} to ${formatClock(entry.clearedAt)}`}
          value={entry.clearedAt === null ? entry.severity : "cleared"}
          valueTone={entry.clearedAt === null ? SEVERITY_TONE[entry.severity] : "dim"}
        />
      ))}
    </Section>
  );
}

export function AlarmsScreen() {
  const remote = useRemote();
  const wide = useWide();
  const alerts = useStore(remote.events.alerts);
  const [guard, setGuard] = useState<GuardState | null>(null);
  const locked = !useScopes().includes("operate");

  useFocusEffect(useCallback(() => remote.connection.watch((client) => client["guard.watch"]({}), setGuard), [remote]));

  const update = (settings: GuardSettings) =>
    void remote.connection.call((client) => client["guard.update"](settings)).then((result) => {
      if (result.ok) setGuard((current) => (current === null ? current : { ...current, settings: result.value }));
      else remote.show(result.error.message, "bad");
    });

  const open = guard?.active ?? alerts;

  return (
    <Screen>
      <Header alerts={open} guard={guard} />
      <OpenAlerts alerts={open} locked={locked} />
      {wide ? (
        <Columns
          main={
            <>
              <Rules guard={guard} locked={locked} onChange={update} />
              <AlarmLog />
            </>
          }
          side={
            <>
              <Readouts guard={guard} />
              <Calm guard={guard} alerts={open} locked={locked} />
              <Wards guard={guard} />
            </>
          }
        />
      ) : (
        <>
          <Readouts guard={guard} />
          <Calm guard={guard} alerts={open} locked={locked} />
          <Rules guard={guard} locked={locked} onChange={update} />
          <Wards guard={guard} />
          <AlarmLog />
        </>
      )}
    </Screen>
  );
}
