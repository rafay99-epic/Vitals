import { describe, expect, test } from "bun:test";
import { type Connection, type ConnectionState, Store } from "@vitals/client-runtime";
import { type TerminalEvent, DeviceId, TerminalId } from "@vitals/contracts";
import * as Schema from "effect/Schema";

import { TerminalSession } from "../src/state/terminal.ts";

const id = Schema.decodeUnknownSync(TerminalId)("01a173b5-eb03-71ad-ac2e-aa6f5ef2cc9e");

const feed = (): { readonly connection: Connection; readonly emit: (event: TerminalEvent) => void; readonly writes: Array<string> } => {
  let listener: ((event: TerminalEvent) => void) | null = null;
  const writes: Array<string> = [];
  const connection: Connection = {
    state: new Store<ConnectionState>({ _tag: "Idle" }),
    call: async (run) => {
      const client = { "terminal.write": ({ data }: { readonly data: string }) => writes.push(data) };
      run(client as never);
      return { ok: true, value: {} as never };
    },
    watch: (_open, onItem) => {
      listener = onItem as (event: TerminalEvent) => void;
      return () => {
        listener = null;
      };
    },
    wake: () => {},
    suspend: () => {},
    dispose: () => {},
  };
  return { connection, emit: (event) => listener?.(event), writes };
};

const info = { id, title: "zsh", cols: 20, rows: 4, startedAt: 0, running: true, exitCode: null, deviceId: Schema.decodeUnknownSync(DeviceId)("dev-1"), deviceName: "Pixel 9" };

const settle = () => new Promise((resolve) => setTimeout(resolve, 80));

describe("TerminalSession", () => {
  test("draws colours and the cursor, and keeps unchanged rows as the same objects", async () => {
    const { connection, emit } = feed();
    const session = new TerminalSession(connection, id, { cols: 20, rows: 4 });
    session.attach();
    emit({ _tag: "Snapshot", info, history: "plain\r\n\u001b[31mred\u001b[0m ok\r\n$ " });
    await settle();
    const first = session.frame.get();
    expect(first.lines).toHaveLength(4);
    expect(first.lines[0]?.runs.map((run) => run.text).join("")).toBe("plain");
    const red = first.lines[1]?.runs.find((run) => run.text === "red");
    expect(red?.fg).toBe("#ff4d6d");
    expect(first.lines[2]?.runs.some((run) => run.bg === "#f2ec6b")).toBe(true);

    emit({ _tag: "Output", data: "ls" });
    await settle();
    const second = session.frame.get();
    expect(second.lines[0]).toBe(first.lines[0]);
    expect(second.lines[2]).not.toBe(first.lines[2]);
    expect(second.lines[2]?.runs.map((run) => run.text).join("")).toContain("$ ls");
    session.dispose();
  });

  test("coalesces keystrokes into one write and stops input once the shell ends", async () => {
    const { connection, emit, writes } = feed();
    const session = new TerminalSession(connection, id, { cols: 20, rows: 4 });
    session.attach();
    emit({ _tag: "Snapshot", info, history: "" });
    for (const key of "echo hi\r") session.input(key);
    await settle();
    expect(writes).toEqual(["echo hi\r"]);
    emit({ _tag: "Exited", code: 0 });
    await settle();
    session.input("x");
    await settle();
    expect(writes).toEqual(["echo hi\r"]);
    expect(session.frame.get().exited).toBe(true);
    session.dispose();
  });
});
