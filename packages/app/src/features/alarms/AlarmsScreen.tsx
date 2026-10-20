import { useFocusEffect } from "@react-navigation/native";
import type { GuardRule, GuardState } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { Banner, Row, Screen, Section, Stat, TextButton } from "@vitals/ui";
import { useCallback, useState } from "react";
import { Switch, Text, View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { useScopes } from "../../state/useScopes.ts";
import { useStore } from "../../state/useStore.ts";

const RULE_TITLES: Record<GuardRule["kind"], string> = {
  memoryPressure: "Memory pressure critical for 10 s",
  swapGrowth: "Swap above 4 GB and growing",
  cpuSaturated: "CPU above 90% for a minute",
  agentOverload: "Six or more agent processes",
  emulatorStack: "Two or more emulators under pressure",
  thermal: "Thermal pressure serious or worse",
};

export function GuardScreen() {
  const remote = useRemote();
  const alerts = useStore(remote.events.alerts);
  const [state, setState] = useState<GuardState | null>(null);
  const canOperate = useScopes().includes("operate");

  useFocusEffect(useCallback(() => remote.connection.watch((client) => client["guard.watch"]({}), setState), [remote]));

  const update = (next: GuardState["settings"]) =>
    void remote.connection.call((client) => client["guard.update"](next)).then((result) => {
      if (result.ok) setState((current) => (current === null ? current : { ...current, settings: result.value }));
      else remote.show(result.error.message, "bad");
    });

  const active = state?.active ?? alerts;

  return (
    <Screen>
      <View className="mt-4 flex-row gap-6">
        <Stat label="Pressure" value={state?.pressure ?? "--"} tone={state?.pressure === "critical" ? "bad" : state?.pressure === "warning" ? "warn" : "ok"} />
        <Stat label="Thermal" value={state?.thermal ?? "--"} />
        <Stat label="Swap" value={state === null ? "--" : formatBytes(state.swapUsedBytes)} />
      </View>
      {active.map((alert) => (
        <Banner key={alert.id} text={`${alert.summary}. ${alert.plan.summary}.`} tone={alert.severity === "critical" ? "bad" : "warn"} />
      ))}
      <Section title="Calm down">
        <View className="flex-row gap-2">
          <View className="flex-1">
            <TextButton
              label="Calm down now"
              disabled={!canOperate}
              onPress={() => void remote.run({ _tag: "CalmDown", alertId: active[0]?.id ?? null })}
            />
          </View>
          <View className="flex-1">
            <TextButton label="Undo" disabled={!canOperate || state?.calmApplied !== true} onPress={() => void remote.run({ _tag: "UndoCalm" })} />
          </View>
        </View>
        <Text className="mt-2 text-xs text-mute">Pauses idle emulators and lowers agent priority. Nothing is killed. Undo restores everything.</Text>
      </Section>
      <Section title="Groups">
        {(state?.groups ?? [])
          .filter((group) => group.count > 0 && group.group !== "protected")
          .map((group) => (
            <Row key={group.group} label={group.group} value={`${group.count} · ${group.cpuPercent.toFixed(0)}% · ${formatBytes(group.memoryBytes)}`} />
          ))}
      </Section>
      {state === null ? null : (
        <Section title="Rules">
          <View className="flex-row items-center justify-between border-b border-line py-2.5">
            <Text className="text-[15px] text-ink">Pressure Guard</Text>
            <Switch value={state.settings.enabled} disabled={!canOperate} onValueChange={(enabled) => update({ ...state.settings, enabled })} />
          </View>
          {state.settings.rules.map((rule) => (
            <View key={rule.kind} className="flex-row items-center justify-between border-b border-line py-2.5">
              <Text className="flex-1 pr-3 text-[15px] text-ink">{RULE_TITLES[rule.kind]}</Text>
              <Switch
                value={rule.enabled}
                disabled={!canOperate || !state.settings.enabled}
                onValueChange={(enabled) =>
                  update({ ...state.settings, rules: state.settings.rules.map((item) => (item.kind === rule.kind ? { ...item, enabled } : item)) })
                }
              />
            </View>
          ))}
        </Section>
      )}
    </Screen>
  );
}
