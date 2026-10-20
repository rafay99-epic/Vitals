import type { ProcessRow, ProcessesSnapshot } from "@vitals/contracts";

const KEPT = 24;
const FORGET_AFTER_SWEEPS = 30;

export type SortBy = "cpu" | "memory";

export const rowKey = (row: ProcessRow): string => `${String(row.pid)}-${String(row.startTimeMs)}`;

interface Ring {
  readonly cpu: Array<number>;
  readonly memory: Array<number>;
  seenAt: number;
}

const push = (values: Array<number>, value: number): void => {
  values.push(value);
  if (values.length > KEPT) values.shift();
};

export class Trends {
  private readonly rings = new Map<string, Ring>();
  private sweep = 0;

  record(snapshot: ProcessesSnapshot): void {
    this.sweep += 1;
    for (const row of snapshot.rows) {
      const key = rowKey(row);
      const ring = this.rings.get(key) ?? { cpu: [], memory: [], seenAt: this.sweep };
      push(ring.cpu, row.cpuPercent);
      push(ring.memory, row.memoryBytes);
      ring.seenAt = this.sweep;
      this.rings.set(key, ring);
    }
    for (const [key, ring] of this.rings) if (this.sweep - ring.seenAt > FORGET_AFTER_SWEEPS) this.rings.delete(key);
  }

  of(key: string, sortBy: SortBy): ReadonlyArray<number> {
    const ring = this.rings.get(key);
    return ring === undefined ? [] : [...ring[sortBy]];
  }
}
