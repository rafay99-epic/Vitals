import { useFocusEffect } from "@react-navigation/native";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import type { AppsSnapshot, Emulator, ProcessGroupId, ProcessRow, ProcessesSnapshot, RunningApp } from "@vitals/contracts";
import { useCallback, useMemo, useState } from "react";
import { ScrollView, SectionList, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { appSheet, processSheet, usage } from "../sheets/ProcessSheets.tsx";
import { Chip, color, Empty, SearchField, sheet, T, Tap, Title, useDockSpace } from "../ui/index.ts";

type GroupKey = "apps" | Exclude<ProcessGroupId, "protected">;
type SortBy = "cpu" | "memory";

const GROUPS: ReadonlyArray<{ readonly key: GroupKey; readonly label: string; readonly chip: string; readonly tint: string }> = [
  { key: "apps", label: "Open apps", chip: "Apps", tint: color.blue },
  { key: "agents", label: "Agents", chip: "Agents", tint: color.yellow },
  { key: "emulators", label: "Emulators", chip: "Emulators", tint: color.green },
  { key: "devServers", label: "Dev servers", chip: "Dev", tint: color.violet },
  { key: "browsers", label: "Browsers", chip: "Browsers", tint: color.orange },
  { key: "other", label: "Background", chip: "Background", tint: color.tele },
];

const TINT = new Map(GROUPS.map((group) => [group.key, group.tint]));
const COLLAPSED = 3;
const APPS_EVERY_MS = 10_000;

type Item =
  | { readonly kind: "app"; readonly key: string; readonly name: string; readonly app: RunningApp; readonly row: ProcessRow | null }
  | { readonly kind: "process"; readonly key: string; readonly name: string; readonly row: ProcessRow; readonly emulator: Emulator | null };

interface Section {
  readonly key: GroupKey;
  readonly title: string;
  readonly total: number;
  readonly hidden: number;
  readonly data: ReadonlyArray<Item>;
}

const weight = (row: ProcessRow | null, sortBy: SortBy): number => (row === null ? -1 : sortBy === "cpu" ? row.cpuPercent : row.memoryBytes);

/** Groups every open app and process. Open apps are listed once, as apps, not again as processes. */
const itemsOf = (snapshot: ProcessesSnapshot | null, apps: AppsSnapshot | null, sortBy: SortBy): ReadonlyMap<GroupKey, ReadonlyArray<Item>> => {
  const rows = snapshot?.rows ?? [];
  const byPid = new Map(rows.map((row) => [row.pid, row]));
  const appPids = new Set((apps?.running ?? []).map((app) => app.pid));
  const emulators = new Map((apps?.emulators ?? []).flatMap((emulator) => (emulator.pid === null ? [] : [[emulator.pid, emulator] as const])));
  const result = new Map<GroupKey, ReadonlyArray<Item>>();
  const open = (apps?.running ?? [])
    .map((app): Item => ({ kind: "app", key: `app-${String(app.pid)}`, name: app.name, app, row: byPid.get(app.pid) ?? null }))
    .sort((left, right) => weight(right.row, sortBy) - weight(left.row, sortBy));
  result.set("apps", open);
  for (const group of GROUPS) {
    if (group.key === "apps") continue;
    result.set(
      group.key,
      rows
        .filter((row) => row.group === group.key && !appPids.has(row.pid))
        .map((row): Item => ({ kind: "process", key: `${String(row.pid)}-${String(row.startTimeMs)}`, name: row.name, row, emulator: emulators.get(row.pid) ?? null })),
    );
  }
  return result;
};

function ItemRow({ item, tint }: { readonly item: Item; readonly tint: string }) {
  const row = item.row;
  const tags = [row?.paused === true ? "paused" : null, row?.throttled === true ? "slowed" : null, item.kind === "app" && item.app.active ? "in front" : null].filter((tag) => tag !== null);
  const open = () => sheet.open(item.kind === "app" ? appSheet(item.app, item.row) : processSheet(item.row, item.emulator));
  return (
    <Tap onPress={open} accessibilityRole="button" accessibilityLabel={`${item.name}${row === null ? "" : `, ${usage(row)}`}`} scale={0.99} style={styles.row}>
      <View style={[styles.tile, { backgroundColor: tint }]}>
        <T v="strong" color={color.bg}>
          {item.name.charAt(0).toUpperCase()}
        </T>
      </View>
      <View style={styles.rowText}>
        <T v="medium" numberOfLines={1}>
          {item.name}
        </T>
        <T v="small" numberOfLines={1}>
          {row === null ? "Open" : usage(row)}
        </T>
      </View>
      {tags.map((tag) => (
        <View key={tag} style={[styles.tag, tag === "paused" ? styles.tagWarn : null]}>
          <T v="tag" color={tag === "paused" ? color.orange : color.dim}>
            {tag}
          </T>
        </View>
      ))}
    </Tap>
  );
}

export function AppsScreen() {
  const remote = useRemote();
  const insets = useSafeAreaInsets();
  const bottom = useDockSpace();
  const [sortBy, setSortBy] = useState<SortBy>("cpu");
  const [snapshot, setSnapshot] = useState<ProcessesSnapshot | null>(null);
  const [apps, setApps] = useState<AppsSnapshot | null>(null);
  const [filter, setFilter] = useState<GroupKey | "all">("all");
  const [query, setQuery] = useState("");
  const [expanded, setExpanded] = useState<ReadonlySet<GroupKey>>(new Set());

  useFocusEffect(useCallback(() => remote.connection.watch((client) => client["processes.watch"]({ sortBy, limit: 200 }), setSnapshot), [remote, sortBy]));
  useFocusEffect(
    useCallback(() => {
      let live = true;
      const load = () =>
        void remote.connection.call((client) => client["apps.list"]({})).then((result) => {
          if (live && result.ok) setApps(result.value);
        });
      load();
      const timer = setInterval(load, APPS_EVERY_MS);
      return () => {
        live = false;
        clearInterval(timer);
      };
    }, [remote]),
  );

  const items = useMemo(() => itemsOf(snapshot, apps, sortBy), [snapshot, apps, sortBy]);
  const needle = query.trim().toLowerCase();
  const sections = GROUPS.filter((group) => filter === "all" || filter === group.key).flatMap((group): ReadonlyArray<Section> => {
    const all = (items.get(group.key) ?? []).filter((item) => needle === "" || item.name.toLowerCase().includes(needle));
    if (all.length === 0) return [];
    const collapse = filter === "all" && needle === "" && !expanded.has(group.key);
    const data = collapse ? all.slice(0, COLLAPSED) : all;
    return [{ key: group.key, title: group.label, total: all.length, hidden: all.length - data.length, data }];
  });
  const loading = snapshot === null && apps === null;

  const header = (
    <View style={{ paddingTop: insets.top + 6 }}>
      <Title
        right={
          <Tap onPress={() => setSortBy(sortBy === "cpu" ? "memory" : "cpu")} accessibilityRole="button" accessibilityLabel={`Sorted by ${sortBy === "cpu" ? "CPU" : "memory"}. Tap to change.`} hitSlop={10} style={styles.sort}>
            <T v="mono" color={color.yellow}>{`by ${sortBy === "cpu" ? "CPU" : "memory"}`}</T>
          </Tap>
        }
      >
        Apps.
      </Title>
      <SearchField value={query} onChangeText={setQuery} placeholder="Search apps and processes" accessibilityLabel="Search" />
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips} keyboardShouldPersistTaps="handled">
        <Chip label="All" on={filter === "all"} onPress={() => setFilter("all")} />
        {GROUPS.map((group) => {
          const count = items.get(group.key)?.length ?? 0;
          return count === 0 ? null : <Chip key={group.key} label={group.chip} count={count} on={filter === group.key} onPress={() => setFilter(filter === group.key ? "all" : group.key)} />;
        })}
      </ScrollView>
    </View>
  );

  return (
    <SectionList
      style={styles.list}
      sections={sections}
      keyExtractor={(item) => item.key}
      renderItem={({ item, section }) => <ItemRow item={item} tint={TINT.get(section.key) ?? color.tele} />}
      renderSectionHeader={({ section }) => (
        <View style={styles.section}>
          <T v="label">{section.title}</T>
          <T v="label">{String(section.total)}</T>
        </View>
      )}
      renderSectionFooter={({ section }) =>
        section.hidden > 0 ? (
          <Tap onPress={() => setExpanded(new Set([...expanded, section.key]))} accessibilityRole="button" style={styles.more}>
            <T v="strong" color={color.yellow}>{`Show all ${String(section.total)}`}</T>
          </Tap>
        ) : null
      }
      ListHeaderComponent={header}
      ListEmptyComponent={loading ? <Empty title="Reading the Mac." /> : <Empty title="Nothing found" detail={needle === "" ? undefined : `No app or process matches "${query.trim()}".`} />}
      ListFooterComponent={<View style={{ height: bottom }} />}
      stickySectionHeadersEnabled={false}
      keyboardShouldPersistTaps="handled"
      keyboardDismissMode="on-drag"
      initialNumToRender={16}
      maxToRenderPerBatch={12}
      windowSize={9}
    />
  );
}

const styles = StyleSheet.create({
  list: { flex: 1, backgroundColor: color.bg },
  sort: { paddingVertical: 6 },
  chips: { gap: 7, paddingHorizontal: 16, paddingBottom: 10 },
  section: { flexDirection: "row", justifyContent: "space-between", paddingHorizontal: 20, paddingTop: 14, paddingBottom: 4 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 8 },
  tile: { width: 34, height: 34, borderRadius: 10, alignItems: "center", justifyContent: "center" },
  rowText: { flex: 1 },
  tag: { borderWidth: 1, borderColor: color.line2, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2 },
  tagWarn: { borderColor: color.orange },
  more: { paddingLeft: 66, paddingVertical: 8 },
});
