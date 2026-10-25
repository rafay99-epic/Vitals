import { useRemote } from "@vitals/app/connection/useRemote.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import { useScopes } from "@vitals/app/state/useScopes.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import type { Command, GuardRuleKind, MacInfo, ProcessGroupId } from "@vitals/contracts";
import type { LinkTone, Tone } from "@vitals/ui";

import { color } from "../ui/tokens.ts";
import { toast } from "../ui/Toast.tsx";

export interface Access {
  readonly operate: boolean;
  readonly destructive: boolean;
  readonly clipboard: boolean;
  readonly files: boolean;
  readonly browse: boolean;
  readonly change: boolean;
  readonly terminal: boolean;
}

/** What this phone may do on the Mac, as granted in Vitals on the Mac. */
export const useAccess = (): Access => {
  const scopes = useScopes();
  return {
    operate: scopes.includes("operate"),
    destructive: scopes.includes("destructive"),
    clipboard: scopes.includes("clipboard"),
    files: scopes.includes("files"),
    browse: scopes.includes("fsRead"),
    change: scopes.includes("fsWrite"),
    terminal: scopes.includes("terminal"),
  };
};

/** The paired Mac's hardware info, once connected. */
export const useMac = (): MacInfo | null => {
  const state = useStore(useRemote().connection.state);
  return state._tag === "Ready" ? state.hello.mac : null;
};

const LANDED: ReadonlySet<string> = new Set(["done", "running", "pending"]);

export interface Undo {
  readonly command: Command;
  readonly done: string;
}

/**
 * Sends a command and confirms it in a toast, with Undo when the action is reversible.
 * Failures are already shown by `Remote.run`, so this only reports success.
 */
export const send = async (remote: Remote, command: Command, done: string | null, undo?: Undo): Promise<boolean> => {
  const receipt = await remote.run(command);
  if (receipt === null || !LANDED.has(receipt.status)) return false;
  if (done !== null) {
    toast.show(done, undo === undefined ? {} : { action: "Undo", onAction: () => void send(remote, undo.command, undo.done) });
  }
  return true;
};

/** Plain-language names for alarm rules. */
export const ALERT_TITLE: Record<GuardRuleKind, string> = {
  memoryPressure: "Memory is full",
  swapGrowth: "Swap keeps growing",
  cpuSaturated: "CPU is maxed out",
  agentOverload: "Too many agents",
  emulatorStack: "Emulators fighting",
  thermal: "Mac is running hot",
};

/** Plain-language names for process groups. */
export const GROUP_NAME: Record<ProcessGroupId, string> = {
  agents: "Agent",
  emulators: "Emulator",
  devServers: "Dev server",
  browsers: "Browser",
  other: "Background process",
  protected: "System process",
};

/** Maps the shared tone names to mobile colours. */
export const TONE_COLOR: Record<Tone, string> = {
  ink: color.ink,
  ink2: color.ink2,
  dim: color.dim,
  mute: color.mute,
  alarmHigh: color.red,
  alarmMedium: color.orange,
  alarmLow: color.blue,
  black: color.bg,
  pulse: color.green,
  eeg: color.yellow,
  press: color.pink,
  temp: color.orange,
  resp: color.blue,
  oxy: color.violet,
  drip: color.drip,
  tele: color.tele,
  disk: color.mint,
};

export const LINK_COLOR: Record<LinkTone, string> = {
  live: color.green,
  away: color.blue,
  quiet: color.dim,
  warn: color.orange,
  off: color.mute,
};
