import { useFocusEffect } from "@react-navigation/native";
import type { ProcessesSnapshot } from "@vitals/contracts";
import { BedRow, EmptyState, Mono, Segmented, Serif, Sheet, Tag, useWide, WardHeader } from "@vitals/ui";
import { type ReactNode, useCallback, useState } from "react";
import { SectionList, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { TabHeader } from "../../components/TabHeader.tsx";
import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";
import { useNow } from "../../state/useVitals.ts";
import { WARD_NAMES, WARD_ORDER } from "../../state/wards.ts";
import { BedActions } from "./BedActions.tsx";
import { type SortBy, Trends } from "./trends.ts";
import { type Bed, bedLabel, bedMeta, reading, type Ward, wardsOf } from "./wards.ts";

const SORTS = [
  { value: "cpu", label: "By CPU" },
  { value: "memory", label: "By memory" },
] as const;

const CHANNEL = { cpu: "pulse", memory: "press" } as const;

const SORT_COLUMN: Record<SortBy, string> = { cpu: "CPU", memory: "Mem" };

type WardSection = Ward & { readonly data: ReadonlyArray<Bed> };

const sectionsOf = (snapshot: ProcessesSnapshot | null): ReadonlyArray<WardSection> =>
  snapshot === null ? [] : wardsOf(snapshot).map((ward) => ({ ...ward, data: ward.beds }));

const wardLine = (bed: Bed): string => `pid ${String(bed.row.pid)} · ${WARD_NAMES[bed.row.group]} ward`;

function Swept({ count, at }: { readonly count: number; readonly at: number }) {
  const now = useNow(1000);
  return <Text>{`${String(count)} processes · ${String(WARD_ORDER.length)} wards · swept ${String(Math.max(0, Math.round((now - at) / 1000)))} s ago`}</Text>;
}

function Columns({ sortBy }: { readonly sortBy: SortBy }) {
  return (
    <View className="flex-row gap-2 border-b border-line px-[22px] pb-2 pt-4">
      <Tag tone="dim" className="w-[22px]">
        Bed
      </Tag>
      <Tag tone="dim" className="flex-1">
        Process
      </Tag>
      <Tag tone="dim" className="w-14">
        Trend
      </Tag>
      <Tag tone="dim" className="w-12 text-right">
        {SORT_COLUMN[sortBy]}
      </Tag>
    </View>
  );
}

function Inspector({ bed, onDone }: { readonly bed: Bed | null; readonly onDone: () => void }) {
  if (bed === null) {
    return (
      <View className="w-[340px] border-l border-line">
        <EmptyState title="No bed selected." detail="Pick a process to see its numbers and orders." />
      </View>
    );
  }
  return (
    <View className="w-[340px] border-l border-line">
      <View className="gap-1 px-[22px] pb-3.5 pt-5">
        <Serif size="l" numberOfLines={1}>
          {bed.row.name}
        </Serif>
        <Mono>{wardLine(bed)}</Mono>
      </View>
      <BedActions row={bed.row} onDone={onDone} />
    </View>
  );
}

function ListTop({ snapshot, sortBy, wide, onSort }: { readonly snapshot: ProcessesSnapshot | null; readonly sortBy: SortBy; readonly wide: boolean; readonly onSort: (next: SortBy) => void }) {
  return (
    <View>
      <TabHeader title="Ward." meta={snapshot === null ? "sweeping" : <Swept count={snapshot.rows.length} at={snapshot.at} />} />
      <Segmented options={SORTS} value={sortBy} onChange={onSort} />
      {snapshot === null ? <EmptyState title="Waiting for the first sweep." detail="Vitals reads every process on the Mac every 2 s. The ward fills in a moment." /> : null}
      {wide && snapshot !== null ? <Columns sortBy={sortBy} /> : null}
    </View>
  );
}

function WardShell({ wide, side, children }: { readonly wide: boolean; readonly side: ReactNode; readonly children: ReactNode }) {
  const insets = useSafeAreaInsets();
  return (
    <View className={`flex-1 bg-bg ${wide ? "flex-row" : ""}`} style={{ paddingTop: insets.top }}>
      <View className="flex-1">{children}</View>
      {side}
    </View>
  );
}

export function WardScreen() {
  const remote = useRemote();
  const wide = useWide();
  const [sortBy, setSortBy] = useState<SortBy>("cpu");
  const [snapshot, setSnapshot] = useState<ProcessesSnapshot | null>(null);
  const [trends] = useState(() => new Trends());
  const [selected, setSelected] = useState<string | null>(null);

  useFocusEffect(
    useCallback(
      () =>
        remote.connection.watch(
          (client) => client["processes.watch"]({ sortBy, limit: 80 }),
          (next) => {
            trends.record(next);
            setSnapshot(next);
          },
        ),
      [remote, sortBy, trends],
    ),
  );

  const sections = sectionsOf(snapshot);
  const chosen = sections.flatMap((section) => section.data).find((bed) => bed.key === selected) ?? null;
  const close = () => setSelected(null);
  const changeSort = (next: SortBy) => {
    haptics.select();
    setSortBy(next);
  };

  const renderBed = ({ item }: { readonly item: Bed }) => {
    const value = reading(item.row, sortBy);
    return (
      <BedRow
        bed={item.bed}
        name={item.row.name}
        meta={bedMeta(item.row)}
        channel={CHANNEL[sortBy]}
        trend={trends.of(item.key, sortBy)}
        value={value.value}
        unit={value.unit}
        paused={item.row.paused}
        selected={wide && item.key === selected}
        onPress={() => {
          haptics.select();
          setSelected(item.key);
        }}
        accessibilityLabel={bedLabel(item.row)}
      />
    );
  };

  const side = wide ? (
    <Inspector bed={chosen} onDone={close} />
  ) : (
    <Sheet visible={chosen !== null} title={chosen?.row.name ?? ""} detail={chosen === null ? undefined : wardLine(chosen)} onClose={close}>
      {chosen === null ? null : <BedActions row={chosen.row} onDone={close} />}
    </Sheet>
  );

  return (
    <WardShell wide={wide} side={side}>
      <SectionList
        sections={sections}
        keyExtractor={(bed) => bed.key}
        renderItem={renderBed}
        renderSectionHeader={({ section }) => <WardHeader name={section.name} totals={section.totals} />}
        ListHeaderComponent={<ListTop snapshot={snapshot} sortBy={sortBy} wide={wide} onSort={changeSort} />}
        extraData={`${sortBy}:${selected ?? ""}`}
        stickySectionHeadersEnabled={false}
        initialNumToRender={14}
        maxToRenderPerBatch={10}
        windowSize={7}
        contentContainerClassName="pb-16"
      />
    </WardShell>
  );
}
