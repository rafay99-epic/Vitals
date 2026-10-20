import type { ProcessRow, ProcessesSnapshot } from "@vitals/contracts";

const KEPT = 24;

export type SortBy = "cpu" | "memory";

export const rowKey = (row: ProcessRow): string => `${String(row.pid)}-${String(row.startTimeMs)}`;

interface Ring {
  readonly cpu: Array<number>;
  readonly memory: Array<number>;
}

const push = (values: Array<number>, value: number): void => {
  values.push(value);
  if (values.length > KEPT) values.shift();
};

export class Trends {
  private readonly rings = new Map<string, Ring>();

  record(snapshot: ProcessesSnapshot): void {
    const seen = new Set<string>();
    for (const row of snapshot.rows) {
      const key = rowKey(row);
      seen.add(key);
      const ring = this.rings.get(key) ?? { cpu: [], memory: [] };
      push(ring.cpu, row.cpuPercent);
      push(ring.memory, row.memoryBytes);
      this.rings.set(key, ring);
    }
    for (const key of this.rings.keys()) if (!seen.has(key)) this.rings.delete(key);
  }

  of(key: string, sortBy: SortBy): ReadonlyArray<number> {
    const ring = this.rings.get(key);
    return ring === undefined ? [] : [...ring[sortBy]];
  }
}
