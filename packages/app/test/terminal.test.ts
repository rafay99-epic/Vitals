import { describe, expect, test } from "bun:test";
import { type Connection, type ConnectionState, Store } from "@vitals/client-runtime";
import { type TerminalEvent, DeviceId, TerminalId } from "@vitals/contracts";
import * as Schema from "effect/Schema";

import { type TerminalSink, TerminalSession } from "../src/state/terminal.ts";
import { XtermScreen } from "../src/state/xtermScreen.ts";

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
  test("pipes the snapshot then live output into the attached screen, resetting on every attach", () => {
    const { connection, emit } = feed();
    const session = new TerminalSession(connection, id, { cols: 20, rows: 4 });
    const seen: Array<string> = [];
    const sink: TerminalSink = { reset: () => seen.push("reset"), write: (data) => seen.push(data) };
    session.attach(sink);
    emit({ _tag: "Snapshot", info, history: "$ " });
    emit({ _tag: "Output", data: "ls" });
    session.detach();
    emit({ _tag: "Output", data: "lost" });
    session.attach(sink);
    emit({ _tag: "Snapshot", info, history: "$ ls" });
    expect(seen).toEqual(["reset", "$ ", "ls", "reset", "$ ls"]);
    expect(session.status.get()).toEqual({ exited: false, exitCode: null, attached: true });
    session.dispose();
  });

  test("coalesces keystrokes into one write and stops input once the shell ends", async () => {
    const { connection, emit, writes } = feed();
    const session = new TerminalSession(connection, id, { cols: 20, rows: 4 });
    session.attach({ reset: () => {}, write: () => {} });
    emit({ _tag: "Snapshot", info, history: "" });
    for (const key of "echo hi\r") session.input(key);
    await settle();
    expect(writes).toEqual(["echo hi\r"]);
    emit({ _tag: "Exited", code: 0 });
    session.input("x");
    await settle();
    expect(writes).toEqual(["echo hi\r"]);
    expect(session.status.get().exited).toBe(true);
    session.dispose();
  });
});

describe("XtermScreen", () => {
  test("draws colours and the cursor, and keeps unchanged rows as the same objects", async () => {
    const screen = new XtermScreen({ cols: 20, rows: 4 }, () => {});
    screen.reset();
    screen.write("plain\r\n\u001b[31mred\u001b[0m ok\r\n$ ");
    await settle();
    const first = screen.lines.get();
    expect(first).toHaveLength(4);
    expect(first[0]?.runs.map((run) => run.text).join("")).toBe("plain");
    expect(first[1]?.runs.find((run) => run.text === "red")?.fg).toBe("#ff4d6d");
    expect(first[2]?.runs.some((run) => run.bg === "#f2ec6b")).toBe(true);

    screen.write("ls");
    await settle();
    const second = screen.lines.get();
    expect(second[0]).toBe(first[0]);
    expect(second[2]).not.toBe(first[2]);
    expect(second[2]?.runs.map((run) => run.text).join("")).toContain("$ ls");
  });
});
