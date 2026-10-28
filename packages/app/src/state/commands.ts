import type { CommandStatus, CommandTag, Scope } from "@vitals/contracts";
import { motion, type Tone } from "@vitals/ui";

const LABELS: ReadonlyMap<string, string> = new Map<CommandTag, string>([
  ["KeepAwake", "Stay awake"],
  ["AllowSleep", "Allow sleep"],
  ["DisplayOff", "Lights out"],
  ["Lock", "Lock"],
  ["Sleep", "Rest"],
  ["Restart", "Restart"],
  ["ShutDown", "Shut down"],
  ["LogOut", "Log out"],
  ["Processes", "Process order"],
  ["QuitApp", "Quit app"],
  ["HideApp", "Hide app"],
  ["ForceQuitApp", "Force quit"],
  ["LaunchApp", "Launch app"],
  ["StopEmulator", "Stop emulator"],
  ["SetVolume", "Volume"],
  ["SetMuted", "Mute"],
  ["ClipboardSet", "Copy to Mac"],
  ["OpenUrl", "Open on Mac"],
  ["Locate", "Locate"],
  ["CalmDown", "Calm down"],
  ["UndoCalm", "Undo calm"],
]);

export const orderLabel = (kind: string): string => LABELS.get(kind) ?? kind;

export const STATUS_TONE: Record<CommandStatus, Tone> = {
  pending: "dim",
  running: "dim",
  done: "pulse",
  failed: "alarmHigh",
  cancelled: "dim",
  rejected: "alarmHigh",
};

export const CONSENT_HINT = `hold ${String(motion.consent / 1000)} s`;

export const scopeLine = (scopes: ReadonlyArray<Scope>): string => scopes.join(" · ");
