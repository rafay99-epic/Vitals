import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { bytes } from "@vitals/app/state/vitals.ts";
import type { Command, Emulator, ProcessActionKind, ProcessRow, RunningApp } from "@vitals/contracts";

import { GROUP_NAME, send, useAccess } from "../lib/remote.ts";
import { ActionRow, Hold, sheet, SheetCancel, SheetHeader, SheetNote } from "../ui/index.ts";

const act = (row: ProcessRow, action: ProcessActionKind): Command => ({
  _tag: "Processes",
  actions: [{ target: { pid: row.pid, startTimeMs: row.startTimeMs }, action }],
});

/** "38% CPU · 1.2 GB" for a process row. */
export const usage = (row: ProcessRow): string => {
  const memory = bytes(row.memoryBytes);
  return `${row.cpuPercent.toFixed(0)}% CPU · ${memory.value} ${memory.unit}`;
};

const WATCH_ONLY = "This phone can only watch. Turn on control for it in Vitals on the Mac.";

/** Actions for one process. Reversible ones are taps with Undo; ending it needs a hold. */
export function processSheet(row: ProcessRow, emulator: Emulator | null) {
  return function ProcessSheet() {
    const remote = useRemote();
    const access = useAccess();
    const run = (command: Command, done: string, undo?: { readonly command: Command; readonly done: string }) => {
      sheet.close();
      void send(remote, command, done, undo);
    };
    return (
      <>
        <SheetHeader title={row.name} detail={`${GROUP_NAME[row.group]} · ${usage(row)} · pid ${String(row.pid)}`} />
        {row.group === "protected" ? (
          <SheetNote>macOS needs this one. Vitals does not pause, slow or quit it.</SheetNote>
        ) : access.operate ? (
          <>
            {row.paused ? (
              <ActionRow icon="play" label="Resume" detail="Pick up where it stopped" onPress={() => run(act(row, "resume"), `${row.name} resumed`, { command: act(row, "pause"), done: `${row.name} paused` })} />
            ) : (
              <ActionRow icon="pause" label="Pause" detail="Freezes it. Resume any time" onPress={() => run(act(row, "pause"), `${row.name} paused`, { command: act(row, "resume"), done: `${row.name} resumed` })} />
            )}
            {row.throttled ? (
              <ActionRow icon="slow" label="Normal priority" detail="Back to full speed" onPress={() => run(act(row, "unthrottle"), `${row.name} back to normal`, { command: act(row, "throttle"), done: `${row.name} slowed down` })} />
            ) : (
              <ActionRow
                icon="slow"
                label="Slow it down"
                detail="Runs when the Mac is idle"
                onPress={() => run(act(row, "throttle"), `${row.name} slowed down`, { command: act(row, "unthrottle"), done: `${row.name} back to normal` })}
              />
            )}
            <ActionRow
              icon="sun"
              label="Keep Mac awake until it ends"
              onPress={() => run({ _tag: "KeepAwake", until: null, display: false, whileProcess: { pid: row.pid, startTimeMs: row.startTimeMs } }, `Keeping awake until ${row.name} ends`)}
            />
          </>
        ) : (
          <SheetNote>{WATCH_ONLY}</SheetNote>
        )}
        {access.destructive && row.group !== "protected" ? (
          <>
            {emulator === null ? null : <Hold label="Hold to stop this emulator" onCommit={() => run({ _tag: "StopEmulator", kind: emulator.kind, id: emulator.id }, `Stopping ${emulator.name}`)} />}
            <Hold label="Hold to quit" onCommit={() => run(act(row, "terminate"), `Asked ${row.name} to quit`)} />
            <Hold small label="Hold to force quit" onCommit={() => run(act(row, "kill"), `${row.name} force quit`)} />
          </>
        ) : null}
        <SheetCancel />
      </>
    );
  };
}

/** Actions for an open app: hide is a tap, quitting needs a hold. */
export function appSheet(app: RunningApp, row: ProcessRow | null) {
  return function AppSheet() {
    const remote = useRemote();
    const access = useAccess();
    const ref = { pid: app.pid, bundleId: app.bundleId };
    const run = (command: Command, done: string) => {
      sheet.close();
      void send(remote, command, done);
    };
    const detail = [app.active ? "In front" : app.hidden ? "Hidden" : "Open", row === null ? null : usage(row)].filter((part) => part !== null).join(" · ");
    return (
      <>
        <SheetHeader title={app.name} detail={detail} />
        {access.operate ? (
          <>
            {app.hidden ? null : <ActionRow icon="eye" label="Hide" detail="Keeps running out of sight" onPress={() => run({ _tag: "HideApp", app: ref }, `${app.name} hidden`)} />}
            <Hold label="Hold to quit" onCommit={() => run({ _tag: "QuitApp", app: ref }, `Asked ${app.name} to quit`)} />
          </>
        ) : (
          <SheetNote>{WATCH_ONLY}</SheetNote>
        )}
        {access.destructive ? <Hold small label="Hold to force quit" onCommit={() => run({ _tag: "ForceQuitApp", app: ref }, `${app.name} force quit`)} /> : null}
        <SheetCancel />
      </>
    );
  };
}
