const BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"] as const;

export const formatBytes = (bytes: number, digits = 1): string => {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  const exponent = Math.max(0, Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), BYTE_UNITS.length - 1));
  const value = bytes / 1024 ** exponent;
  return `${value.toFixed(exponent === 0 ? 0 : digits)} ${BYTE_UNITS[exponent] ?? "B"}`;
};

export const formatRate = (bytesPerSec: number): string => `${formatBytes(bytesPerSec)}/s`;

export const formatPercent = (value: number | null, digits = 0): string =>
  value === null ? "--" : `${value.toFixed(digits)}%`;

export const formatCelsius = (value: number | null): string => (value === null ? "--" : `${Math.round(value)}°C`);

export const formatWatts = (value: number | null): string =>
  value === null ? "--" : `${value.toFixed(value < 10 ? 1 : 0)} W`;

export const formatRpm = (value: number | null): string => (value === null ? "--" : `${Math.round(value)} rpm`);

export const formatClock = (epochMs: number): string =>
  new Date(epochMs).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

export const formatDateTime = (epochMs: number): string =>
  new Date(epochMs).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
