import type { GroupTotals, ProcessRow, ProcessesSnapshot } from "@vitals/contracts";
import { formatBytes } from "@vitals/shared";

import { bytes, fixed, type Reading } from "../../state/vitals.ts";
import { WARD_NAMES, WARD_ORDER, type WardId } from "../../state/wards.ts";
import { rowKey, type SortBy } from "./trends.ts";

export interface Bed {
  readonly key: string;
  readonly bed: number;
  readonly row: ProcessRow;
}

export interface Ward {
  readonly id: WardId;
  readonly name: string;
  readonly totals: string;
  readonly beds: ReadonlyArray<Bed>;
}

const totalsLine = (totals: GroupTotals | undefined, count: number): string =>
  totals === undefined ? `${String(count)} beds` : `${String(totals.count)} beds · ${totals.cpuPercent.toFixed(0)}% · ${formatBytes(totals.memoryBytes)}`;

export const wardsOf = (snapshot: ProcessesSnapshot): ReadonlyArray<Ward> => {
  const totals = new Map(snapshot.groups.map((group) => [group.group, group]));
  let next = 1;
  return WARD_ORDER.flatMap((id) => {
    const rows = snapshot.rows.filter((row) => row.group === id);
    if (rows.length === 0) return [];
    const beds = rows.map((row) => ({ key: rowKey(row), bed: next++, row }));
    return [{ id, name: WARD_NAMES[id], totals: totalsLine(totals.get(id), rows.length), beds }];
  });
};

export const reading = (row: ProcessRow, sortBy: SortBy): Reading =>
  sortBy === "cpu" ? { value: fixed(row.cpuPercent), unit: "% cpu" } : bytes(row.memoryBytes);

export const bedMeta = (row: ProcessRow): string => `pid ${String(row.pid)}${row.throttled ? " · low priority" : ""}`;

export const bedLabel = (row: ProcessRow): string => {
  const memory = bytes(row.memoryBytes);
  return `${row.name}, process ${String(row.pid)}, ${row.cpuPercent.toFixed(0)} percent CPU, ${memory.value} ${memory.unit}${row.paused ? ", paused" : ""}. Actions available.`;
};
