const HOUR = 3_600_000;

export type StayAwake = "1h" | "4h" | "morning" | "forever";

export const STAY_OPTIONS: ReadonlyArray<{ readonly value: StayAwake; readonly label: string }> = [
  { value: "1h", label: "1 h" },
  { value: "4h", label: "4 h" },
  { value: "morning", label: "Until 8 am here" },
  { value: "forever", label: "Forever" },
];

const nextMorning = (now: number): number => {
  const date = new Date(now);
  date.setDate(date.getHours() >= 8 ? date.getDate() + 1 : date.getDate());
  date.setHours(8, 0, 0, 0);
  return date.getTime();
};

export const stayUntil: Record<StayAwake, (now: number) => number | null> = {
  "1h": (now) => now + HOUR,
  "4h": (now) => now + 4 * HOUR,
  morning: nextMorning,
  forever: () => null,
};

export const AWAY_MS = 4 * HOUR;
export const GRACE_SECONDS = 10;
