import type { GuardRule, GuardRuleKind, MemoryPressure, ThermalState } from "@vitals/contracts";
import type { Tone } from "@vitals/ui";

const held = (seconds: number): string => {
  if (seconds === 0) return "at once";
  return seconds < 60 ? `for ${String(seconds)} s` : `for ${String(Math.round(seconds / 60))} min`;
};

const PRESSURE_LEVEL = ["normal", "warning", "critical"] as const;
const THERMAL_LEVEL = ["nominal", "fair", "serious", "critical"] as const;

const level = (names: ReadonlyArray<string>, threshold: number): string => names[Math.max(0, Math.ceil(threshold))] ?? String(threshold);

export const RULES: Record<GuardRuleKind, { readonly title: string; readonly detail: (rule: GuardRule) => string }> = {
  memoryPressure: { title: "Memory pressure", detail: (rule) => `${level(PRESSURE_LEVEL, rule.threshold)} ${held(rule.holdSeconds)}` },
  swapGrowth: { title: "Swap growing", detail: (rule) => `above ${String(rule.threshold)} GB and still growing ${held(rule.holdSeconds)}` },
  cpuSaturated: { title: "CPU saturated", detail: (rule) => `above ${String(rule.threshold)}% ${held(rule.holdSeconds)}` },
  agentOverload: { title: "Agent crowd", detail: (rule) => `${String(rule.threshold)} or more agents ${held(rule.holdSeconds)}` },
  emulatorStack: { title: "Emulators fighting", detail: (rule) => `${String(rule.threshold)} or more emulators under pressure ${held(rule.holdSeconds)}` },
  thermal: { title: "Thermal", detail: (rule) => `${level(THERMAL_LEVEL, rule.threshold)} or worse ${held(rule.holdSeconds)}` },
};

export const PRESSURE_TONE: Record<MemoryPressure, Tone> = { normal: "ink", warning: "alarmMedium", critical: "alarmHigh" };

export const THERMAL_TONE: Record<ThermalState, Tone> = { nominal: "ink", fair: "temp", serious: "alarmMedium", critical: "alarmHigh" };
