import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { type TerminalEvent, type ToApp, DeviceId } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { replayable } from "../src/terminal/TerminalService.ts";
import { type Gateway, adminOp, pairDevice, startGateway, withClient } from "./harness.ts";

const deviceIdOf = Schema.decodeUnknownSync(DeviceId);

let gateway: Gateway | null = null;
let home = "";
let previousShell: string | undefined;

beforeEach(() => {
  previousShell = process.env["SHELL"];
  process.env["SHELL"] = "/bin/sh";
  home = realpathSync(mkdtempSync(join(tmpdir(), "vitals-term-home-")));
});

afterEach(async () => {
  await gateway?.stop();
  gateway = null;
  if (previousShell === undefined) delete process.env["SHELL"];
  else process.env["SHELL"] = previousShell;
  rmSync(home, { recursive: true, force: true });
});

const allowed = async () => {
  gateway = await startGateway(join(mkdtempSync(join(tmpdir(), "vitals-data-")), "remote"), home);
  const device = await pairDevice(gateway);
  await adminOp(gateway.app, { _tag: "SetScopes", deviceId: deviceIdOf(device.deviceId), scopes: ["read", "operate", "files", "fsRead", "terminal"] });
  return { gateway, ...device };
};

const textOf = (events: ReadonlyArray<TerminalEvent>): string =>
  events.map((event) => (event._tag === "Snapshot" ? event.history : event._tag === "Output" ? event.data : "")).join("");

const macTerminals = (received: ReadonlyArray<ToApp>) => received.filter((message): message is Extract<ToApp, { t: "terminals" }> => message.t === "terminals");

describe("terminal", () => {
  test("replayed history drops queries that would make the phone answer again", () => {
    const esc = String.fromCharCode(27);
    const history = `ok${esc}[6n${esc}[c${esc}[>0c${esc}]11;?${String.fromCharCode(7)}${esc}[31mred${esc}[0m`;
    expect(replayable(history)).toBe(`ok${esc}[31mred${esc}[0m`);
  });

  test("is off until the Mac allows it", async () => {
    gateway = await startGateway(join(mkdtempSync(join(tmpdir(), "vitals-data-")), "remote"), home);
    const { token, scopes } = await pairDevice(gateway);
    expect(scopes).not.toContain("terminal");
    const refused = await withClient(gateway, token, (client) => Effect.flip(client["terminal.open"]({ cols: 80, rows: 24 })));
    expect(refused).toMatchObject({ _tag: "AuthError" });
  });

  test("runs a real shell, streams output, replays it on re-attach, and ends on close", async () => {
    const { gateway: target, token } = await allowed();
    const result = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const opened = yield* client["terminal.open"]({ cols: 100, rows: 30 });
        const live = yield* client["terminal.attach"]({ id: opened.id, cols: 100, rows: 30 }).pipe(
          Stream.tap((event) => (event._tag === "Snapshot" ? client["terminal.write"]({ id: opened.id, data: "printf 'vitals-%s\\n' ok\n" }) : Effect.void)),
          Stream.takeUntil((event) => event._tag === "Output" && event.data.includes("vitals-ok")),
          Stream.runCollect,
        );
        const again = yield* client["terminal.attach"]({ id: opened.id, cols: 100, rows: 30 }).pipe(Stream.take(1), Stream.runCollect);
        const listed = yield* client["terminal.list"]({});
        const exit = yield* client["terminal.attach"]({ id: opened.id, cols: 100, rows: 30 }).pipe(
          Stream.tap((event) => (event._tag === "Snapshot" ? client["terminal.close"]({ id: opened.id }) : Effect.void)),
          Stream.takeUntil((event) => event._tag === "Exited"),
          Stream.runCollect,
        );
        return { opened, live, again, listed, exit };
      }),
    );
    expect(result.opened).toMatchObject({ cols: 100, rows: 30, running: true, title: "sh" });
    expect(textOf(result.live)).toContain("vitals-ok");
    expect(result.again[0]?._tag).toBe("Snapshot");
    expect(textOf(result.again)).toContain("vitals-ok");
    expect(result.listed.sessions.map((session) => session.id)).toContain(result.opened.id);
    expect(result.exit.at(-1)?._tag).toBe("Exited");

    const told = macTerminals(target.app.received);
    expect(told.some((message) => message.sessions.some((session) => session.id === result.opened.id))).toBe(true);
    expect(told.at(-1)?.sessions).toEqual([]);
  });

  test("the Mac can end every terminal a device has open", async () => {
    const { gateway: target, token, deviceId } = await allowed();
    const ended = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const opened = yield* client["terminal.open"]({ cols: 80, rows: 24 });
        return yield* client["terminal.attach"]({ id: opened.id, cols: 80, rows: 24 }).pipe(
          Stream.tap((event) => (event._tag === "Snapshot" ? Effect.sync(() => target.app.emit({ t: "terminalEnd", id: null, deviceId: deviceIdOf(deviceId) })) : Effect.void)),
          Stream.takeUntil((event) => event._tag === "Exited"),
          Stream.runCollect,
        );
      }),
    );
    expect(ended.at(-1)?._tag).toBe("Exited");
  });
});
