import type { Command, ProcessActionKind, ProcessRow } from "@vitals/contracts";
import { HoldRow, KeyValueGrid, SheetAction } from "@vitals/ui";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";
import { CONSENT_HINT } from "../../state/commands.ts";
import { useScopes } from "../../state/useScopes.ts";
import { bytes, fixed } from "../../state/vitals.ts";

const act = (row: ProcessRow, action: ProcessActionKind): Command => ({
  _tag: "Processes",
  actions: [{ target: { pid: row.pid, startTimeMs: row.startTimeMs }, action }],
});

function ConsentAction({ label, hint, onCommit }: { readonly label: string; readonly hint: string; readonly onCommit: () => void }) {
  return <HoldRow label={label} hint={hint} kind="consent" danger compact onStart={haptics.soft} onCommit={onCommit} />;
}

export function BedActions({ row, onDone }: { readonly row: ProcessRow; readonly onDone: () => void }) {
  const remote = useRemote();
  const scopes = useScopes();
  const operate = scopes.includes("operate");
  const destructive = scopes.includes("destructive");
  const memory = bytes(row.memoryBytes);

  const run = (command: Command) => {
    haptics.success();
    onDone();
    void remote.run(command);
  };

  const finish = (command: Command) => {
    haptics.heavy();
    onDone();
    void remote.run(command);
  };

  return (
    <View>
      <KeyValueGrid
        items={[
          { key: "CPU", value: fixed(row.cpuPercent), unit: "%", tone: "pulse" },
          { key: "Memory", value: memory.value, unit: memory.unit, tone: "press" },
        ]}
      />
      {operate ? (
        <>
          <SheetAction
            label={row.paused ? "Resume" : "Pause"}
            detail={row.paused ? "SIGCONT" : "SIGSTOP · resume any time"}
            tone={row.paused ? "resp" : "ink"}
            onPress={() => run(act(row, row.paused ? "resume" : "pause"))}
          />
          <SheetAction
            label={row.throttled ? "Normal priority" : "Lower priority"}
            detail={row.throttled ? "back to nice 0" : "runs when the Mac is idle"}
            onPress={() => run(act(row, row.throttled ? "unthrottle" : "throttle"))}
          />
          <SheetAction
            label="Keep Mac awake while it runs"
            detail="ends when the process exits"
            onPress={() => run({ _tag: "KeepAwake", until: null, display: false, whileProcess: { pid: row.pid, startTimeMs: row.startTimeMs } })}
          />
        </>
      ) : null}
      {destructive ? (
        <>
          <ConsentAction label="Quit" hint={`SIGTERM · asks it to close · ${CONSENT_HINT}`} onCommit={() => finish(act(row, "terminate"))} />
          <ConsentAction label="Kill" hint={`SIGKILL · unsaved work is lost · ${CONSENT_HINT}`} onCommit={() => finish(act(row, "kill"))} />
        </>
      ) : null}
    </View>
  );
}
