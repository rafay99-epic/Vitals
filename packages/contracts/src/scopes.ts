import type { Scope } from "./auth.ts";
import { type Command, isDestructive } from "./commands.ts";
import type { VitalsMethod } from "./rpc.ts";

type ScopeRule = Scope | ((payload: unknown) => Scope);

export const commandScope = (command: Command): Scope => (isDestructive(command) ? "destructive" : "operate");

const hasCommand = (payload: unknown): payload is { readonly command: Command } =>
  typeof payload === "object" && payload !== null && "command" in payload;

export const RPC_SCOPES = {
  "server.hello": "read",
  "stats.live": "read",
  "history.range": "read",
  "system.events": "read",
  "processes.watch": "read",
  "apps.list": "read",
  "command.run": (payload) => (hasCommand(payload) ? commandScope(payload.command) : "destructive"),
  "command.cancel": "operate",
  "command.log": "read",
  "guard.watch": "read",
  "guard.update": "operate",
  "clipboard.get": "clipboard",
  "activity.ingest": "read",
  "device.lanKey": "read",
  "device.forget": "read",
} as const satisfies Record<VitalsMethod, ScopeRule>;

export const requiredScope = (method: VitalsMethod, payload: unknown): Scope => {
  const rule: ScopeRule = RPC_SCOPES[method];
  return typeof rule === "function" ? rule(payload) : rule;
};
