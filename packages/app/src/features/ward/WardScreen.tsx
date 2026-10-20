import { useFocusEffect } from "@react-navigation/native";
import type { ProcessActionKind, ProcessGroupId, ProcessRow, ProcessesSnapshot } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";
import { Row, Screen, Section, Segmented, useActionMenu } from "@vitals/ui";
import { useCallback, useState } from "react";
import { Text, View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { useScopes } from "../../state/useScopes.ts";

const GROUPS: ReadonlyArray<{ readonly id: ProcessGroupId; readonly title: string }> = [
  { id: "agents", title: "Agents" },
  { id: "emulators", title: "Emulators" },
  { id: "devServers", title: "Dev servers" },
  { id: "browsers", title: "Browsers" },
  { id: "other", title: "Other" },
];

export function ProcessesScreen() {
  const remote = useRemote();
  const [sortBy, setSortBy] = useState<"cpu" | "memory">("cpu");
  const [snapshot, setSnapshot] = useState<ProcessesSnapshot | null>(null);
  const [menuElement, openMenu] = useActionMenu();
  const scopes = useScopes();

  useFocusEffect(
    useCallback(
      () => remote.connection.watch((client) => client["processes.watch"]({ sortBy, limit: 80 }), setSnapshot),
      [remote, sortBy],
    ),
  );

  const act = (row: ProcessRow, action: ProcessActionKind) =>
    void remote.run({ _tag: "Processes", actions: [{ target: { pid: row.pid, startTimeMs: row.startTimeMs }, action }] });

  const menu = (row: ProcessRow) =>
    openMenu({
      title: row.name,
      detail: `pid ${row.pid} · ${row.cpuPercent.toFixed(0)}% CPU · ${formatBytes(row.memoryBytes)}`,
      actions: [
        row.throttled ? { label: "Normal priority", onPress: () => act(row, "unthrottle") } : { label: "Lower priority", onPress: () => act(row, "throttle") },
        row.paused ? { label: "Resume", onPress: () => act(row, "resume") } : { label: "Pause", onPress: () => act(row, "pause") },
        {
          label: "Keep Mac awake while it runs",
          onPress: () => void remote.run({ _tag: "KeepAwake", until: null, display: false, whileProcess: { pid: row.pid, startTimeMs: row.startTimeMs } }),
        },
        ...(scopes.includes("destructive")
          ? [
              { label: "Quit (SIGTERM)", tone: "bad" as const, onPress: () => act(row, "terminate") },
              { label: "Kill (SIGKILL)", tone: "bad" as const, onPress: () => act(row, "kill") },
            ]
          : []),
      ],
    });

  const groupTotals = new Map((snapshot?.groups ?? []).map((group) => [group.group, group]));

  return (
    <Screen>
      {menuElement}
      <View className="mt-4">
        <Segmented
          options={[
            { value: "cpu", label: "BY CPU" },
            { value: "memory", label: "BY MEMORY" },
          ]}
          value={sortBy}
          onChange={setSortBy}
        />
      </View>
      {snapshot === null ? <Text className="mt-6 text-sm text-mute">Waiting for the first sweep</Text> : null}
      {GROUPS.map(({ id, title }) => {
        const rows = (snapshot?.rows ?? []).filter((row) => row.group === id);
        const totals = groupTotals.get(id);
        if (rows.length === 0) return null;
        return (
          <Section
            key={id}
            title={`${title} · ${totals?.count ?? rows.length}`}
            trailing={
              totals === undefined ? null : (
                <Text className="font-mono text-[11px] text-mute">{`${totals.cpuPercent.toFixed(0)}% · ${formatBytes(totals.memoryBytes)}`}</Text>
              )
            }
          >
            {rows.map((row) => (
              <Row
                key={`${row.pid}-${row.startTimeMs}`}
                label={row.name}
                detail={`pid ${row.pid}${row.throttled ? " · low priority" : ""}${row.paused ? " · paused" : ""}`}
                value={sortBy === "cpu" ? `${row.cpuPercent.toFixed(0)}%` : formatBytes(row.memoryBytes)}
                tone={row.paused ? "warn" : row.cpuPercent > 80 ? "bad" : "ink"}
                onPress={() => menu(row)}
              />
            ))}
          </Section>
        );
      })}
    </Screen>
  );
}
