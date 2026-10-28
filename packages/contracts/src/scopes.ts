import type { Scope } from "./auth.ts";
import { type Command, isDestructive } from "./commands.ts";
import type { VitalsMethod } from "./rpc.ts";

type ScopeRule = Scope | ((payload: unknown) => Scope);

export const commandScope = (command: Command): Scope => (isDestructive(command) ? "destructive" : "operate");

const hasCommand = (payload: unknown): payload is { readonly command: Command } =>
  typeof payload === "object" && payload !== null && "command" in payload;

const hasDestination = (payload: unknown): boolean =>
  typeof payload === "object" && payload !== null && "dest" in payload && typeof payload.dest === "string";

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
  "system.audio": "read",
  "guard.update": "operate",
  "clipboard.get": "clipboard",
  "clips.watch": "clipboard",
  "clips.read": "clipboard",
  "clips.pin": "clipboard",
  "clips.remove": "clipboard",
  "clips.send.begin": "operate",
  "clips.send.chunk": "operate",
  "clips.send.finish": "operate",
  "clips.put": "operate",
  "drop.watch": "files",
  "drop.offer": (payload) => (hasDestination(payload) ? "fsWrite" : "files"),
  "drop.accept": "files",
  "drop.decline": "files",
  "drop.cancel": "files",
  "drop.ticket": "files",
  "drop.received": "files",
  "fs.roots": "fsRead",
  "fs.devices": "fsRead",
  "fs.serve": "files",
  "fs.reply": "files",
  "fs.pull": "fsRead",
  "fs.list": "fsRead",
  "fs.search": "fsRead",
  "fs.thumbs": "fsRead",
  "fs.get": "fsRead",
  "fs.open": "operate",
  "fs.recent": "fsRead",
  "fs.transfer": "fsRead",
  "fs.read": "fsRead",
  "terminal.list": "terminal",
  "terminal.open": "terminal",
  "terminal.attach": "terminal",
  "terminal.write": "terminal",
  "terminal.resize": "terminal",
  "terminal.close": "terminal",
  "activity.ingest": "read",
  "activity.clear": "read",
  "device.lanKey": "read",
  "device.forget": "read",
} as const satisfies Record<VitalsMethod, ScopeRule>;

export const requiredScope = (method: VitalsMethod, payload: unknown): Scope => {
  const rule: ScopeRule = RPC_SCOPES[method];
  return typeof rule === "function" ? rule(payload) : rule;
};
