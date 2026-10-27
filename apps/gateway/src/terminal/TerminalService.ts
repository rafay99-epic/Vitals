import { homedir } from "node:os";
import { basename } from "node:path";

import {
  type DeviceId,
  type MacTerminal,
  type TerminalAttachInput,
  type TerminalEvent,
  type TerminalIdInput,
  type TerminalInfo,
  type TerminalList,
  type TerminalSize,
  type TerminalWriteInput,
  CommandRejected,
  TERMINAL_LIMITS,
  TerminalId,
  Unavailable,
} from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { GatewayConfig } from "../config.ts";
import { Store } from "../persistence/Store.ts";

export interface TerminalCaller {
  readonly deviceId: DeviceId;
  readonly name: string;
}

type TerminalError = Unavailable | CommandRejected;

export class TerminalService extends Context.Service<
  TerminalService,
  {
    readonly list: Effect.Effect<TerminalList>;
    readonly open: (caller: TerminalCaller, size: TerminalSize) => Effect.Effect<TerminalInfo, TerminalError>;
    readonly attach: (caller: TerminalCaller, input: TerminalAttachInput) => Stream.Stream<TerminalEvent, TerminalError>;
    readonly write: (input: TerminalWriteInput) => Effect.Effect<void, TerminalError>;
    readonly resize: (input: TerminalAttachInput) => Effect.Effect<void, TerminalError>;
    readonly close: (caller: TerminalCaller, input: TerminalIdInput) => Effect.Effect<void, TerminalError>;
  }
>()("@vitals/gateway/TerminalService") {}

const FLUSH_MS = 8;
const FLUSH_BYTES = 32 * 1024;
const BEHIND_EVENTS = 512;
const KILL_GRACE_MS = 1_000;
const IDLE_MS = 12 * 60 * 60 * 1000;
const REAP_EVERY = "5 minutes";
const GONE = "That terminal is gone";

const makeId = Schema.decodeUnknownSync(TerminalId);

const ESC = String.fromCharCode(27);
const BEL = String.fromCharCode(7);

const QUERIES = [
  String.raw`\[[0-9;?]*n`,
  String.raw`\[[0-9;?]*R`,
  String.raw`\[[>=]?[0-9;]*c`,
  String.raw`\[[0-9;?]*\$[py]`,
  String.raw`\[>[0-9;]*q`,
  String.raw`\](?:10|11|12);\?(?:${BEL}|${ESC}\\)`,
  String.raw`P[01]?[$+][qr][^${ESC}]*${ESC}\\`,
].map((body) => new RegExp(`${ESC}${body}`, "g"));

export const replayable = (history: string): string => QUERIES.reduce((text, pattern) => text.replace(pattern, ""), history);

const trimHistory = (history: string): string => {
  if (history.length <= TERMINAL_LIMITS.history) return history;
  const cut = history.length - TERMINAL_LIMITS.history;
  const line = history.indexOf("\n", cut);
  return line === -1 ? history.slice(cut) : history.slice(line + 1);
};

const shellEnv = (): Record<string, string> => {
  const env: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) if (value !== undefined && !key.startsWith("VITALS_")) env[key] = value;
  return { ...env, TERM: "xterm-256color", COLORTERM: "truecolor", LANG: env["LANG"] ?? "en_US.UTF-8" };
};

interface Listener {
  readonly push: (event: TerminalEvent) => void;
}

interface Session {
  readonly id: TerminalId;
  readonly deviceId: DeviceId;
  readonly deviceName: string;
  readonly startedAt: number;
  readonly title: string;
  readonly proc: Bun.Subprocess;
  readonly decoder: TextDecoder;
  readonly listeners: Set<Listener>;
  cols: number;
  rows: number;
  history: string;
  pending: string;
  timer: ReturnType<typeof setTimeout> | null;
  running: boolean;
  exitCode: number | null;
  lastActivity: number;
}

export const layer = Layer.effect(
  TerminalService,
  Effect.gen(function* () {
    const config = yield* GatewayConfig;
    const bridge = yield* Bridge;
    const activity = yield* ActivityLog;
    const store = yield* Store;
    const home = config.homeDir ?? homedir();
    const shell = process.env["SHELL"] ?? "/bin/zsh";
    const sessions = new Map<string, Session>();

    const info = (session: Session): TerminalInfo => ({
      id: session.id,
      title: session.title,
      cols: session.cols,
      rows: session.rows,
      startedAt: session.startedAt,
      running: session.running,
      exitCode: session.exitCode,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
    });

    const tellMac = () => {
      const live: Array<MacTerminal> = [...sessions.values()]
        .filter((session) => session.running)
        .map((session) => ({ id: session.id, title: session.title, deviceId: session.deviceId, deviceName: session.deviceName, startedAt: session.startedAt, attached: session.listeners.size }));
      Effect.runFork(bridge.send({ t: "terminals", sessions: live }));
    };

    const log = (kind: string, session: Session, data: Record<string, unknown> = {}) =>
      activity.record({ at: Date.now(), source: "gateway", level: "info", kind, deviceId: session.deviceId, data: { id: session.id, ...data } });

    const flush = (session: Session) => {
      if (session.timer !== null) clearTimeout(session.timer);
      session.timer = null;
      if (session.pending.length === 0) return;
      const event: TerminalEvent = { _tag: "Output", data: session.pending };
      session.pending = "";
      for (const listener of session.listeners) listener.push(event);
    };

    const received = (session: Session, bytes: Uint8Array) => {
      const text = session.decoder.decode(bytes, { stream: true });
      if (text.length === 0) return;
      session.history = trimHistory(session.history + text);
      session.pending += text;
      if (session.pending.length >= FLUSH_BYTES) flush(session);
      else session.timer ??= setTimeout(() => flush(session), FLUSH_MS);
    };

    const ended = (session: Session, code: number | null) => {
      if (!session.running) return;
      flush(session);
      session.running = false;
      session.exitCode = code;
      for (const listener of session.listeners) listener.push({ _tag: "Exited", code });
      log("terminal.exited", session, { code, minutes: Math.round((Date.now() - session.startedAt) / 60_000) });
      sessions.delete(session.id);
      tellMac();
    };

    const stop = (session: Session) => {
      if (!session.running) return;
      session.proc.kill("SIGHUP");
      setTimeout(() => {
        if (session.running) session.proc.kill("SIGKILL");
      }, KILL_GRACE_MS);
    };

    const find = (id: string) => Effect.suspend(() => {
      const session = sessions.get(id);
      return session === undefined ? Effect.fail(new Unavailable({ message: GONE })) : Effect.succeed(session);
    });

    const open = (caller: TerminalCaller, size: TerminalSize) =>
      Effect.gen(function* () {
        const live = [...sessions.values()];
        if (live.length >= TERMINAL_LIMITS.total) return yield* Effect.fail(new CommandRejected({ message: "Your Mac already has as many terminals open as Vitals allows. End one first." }));
        if (live.filter((session) => session.deviceId === caller.deviceId).length >= TERMINAL_LIMITS.perDevice) {
          return yield* Effect.fail(new CommandRejected({ message: `This device already has ${String(TERMINAL_LIMITS.perDevice)} terminals open. End one first.` }));
        }
        const id = makeId(newId());
        const holder: { session: Session | null } = { session: null };
        const proc = yield* Effect.try({
          try: () =>
            Bun.spawn([shell, "-l"], {
              cwd: home,
              env: shellEnv(),
              terminal: {
                cols: size.cols,
                rows: size.rows,
                data: (_terminal, bytes) => {
                  if (holder.session !== null) received(holder.session, bytes);
                },
              },
            }),
          catch: () => new Unavailable({ message: "Your Mac couldn't start a shell" }),
        });
        const session: Session = {
          id,
          deviceId: caller.deviceId,
          deviceName: caller.name,
          startedAt: Date.now(),
          title: basename(shell),
          proc,
          decoder: new TextDecoder(),
          listeners: new Set(),
          cols: size.cols,
          rows: size.rows,
          history: "",
          pending: "",
          timer: null,
          running: true,
          exitCode: null,
          lastActivity: Date.now(),
        };
        holder.session = session;
        sessions.set(id, session);
        void proc.exited.then((code) => ended(session, code));
        log("terminal.opened", session, { shell: session.title });
        tellMac();
        return info(session);
      });

    const attach = (caller: TerminalCaller, input: TerminalAttachInput): Stream.Stream<TerminalEvent, TerminalError> =>
      Stream.unwrap(
        Effect.map(find(input.id), (session) =>
          Stream.callback<TerminalEvent>((queue) =>
            Effect.acquireRelease(
              Effect.sync(() => {
                if (session.cols !== input.cols || session.rows !== input.rows) {
                  session.cols = input.cols;
                  session.rows = input.rows;
                  session.proc.terminal?.resize(input.cols, input.rows);
                }
                flush(session);
                const snapshot = (): TerminalEvent => ({ _tag: "Snapshot", info: info(session), history: replayable(session.history) });
                const listener: Listener = {
                  push: (event) => {
                    if (Queue.sizeUnsafe(queue) > BEHIND_EVENTS) {
                      Effect.runSync(Effect.ignore(Queue.clear(queue)));
                      Queue.offerUnsafe(queue, snapshot());
                      return;
                    }
                    Queue.offerUnsafe(queue, event);
                  },
                };
                Queue.offerUnsafe(queue, snapshot());
                if (!session.running) Queue.offerUnsafe(queue, { _tag: "Exited", code: session.exitCode });
                session.listeners.add(listener);
                log("terminal.attached", session, { by: caller.deviceId });
                tellMac();
                return listener;
              }),
              (listener) =>
                Effect.sync(() => {
                  session.listeners.delete(listener);
                  tellMac();
                }),
            ),
          ),
        ),
      );

    const write = (input: TerminalWriteInput) =>
      Effect.flatMap(find(input.id), (session) =>
        Effect.sync(() => {
          session.proc.terminal?.write(input.data);
          session.lastActivity = Date.now();
        }),
      );

    const resize = (input: TerminalAttachInput) =>
      Effect.flatMap(find(input.id), (session) =>
        Effect.sync(() => {
          if (session.cols === input.cols && session.rows === input.rows) return;
          session.cols = input.cols;
          session.rows = input.rows;
          session.proc.terminal?.resize(input.cols, input.rows);
        }),
      );

    const close = (caller: TerminalCaller, input: TerminalIdInput) =>
      Effect.flatMap(find(input.id), (session) =>
        Effect.sync(() => {
          log("terminal.closed", session, { by: caller.deviceId });
          stop(session);
        }),
      );

    const reap = Effect.sync(() => {
      const cutoff = Date.now() - IDLE_MS;
      for (const session of sessions.values()) {
        const device = store.device(session.deviceId);
        const allowed = device !== null && device.revokedAt === null && device.scopes.includes("terminal");
        if (!allowed || (session.listeners.size === 0 && session.lastActivity < cutoff)) stop(session);
      }
    });
    yield* Effect.sleep(REAP_EVERY).pipe(Effect.andThen(reap), Effect.forever, Effect.forkScoped);

    const inbox = yield* bridge.subscribe;
    yield* Stream.fromSubscription(inbox).pipe(
      Stream.runForEach((message) =>
        Effect.sync(() => {
          if (message.t === "hello") tellMac();
          if (message.t !== "terminalEnd") return;
          for (const session of sessions.values()) if (message.id === null || message.id === session.id || message.deviceId === session.deviceId) stop(session);
        }),
      ),
      Effect.forkScoped,
    );

    yield* Effect.addFinalizer(() =>
      Effect.sync(() => {
        for (const session of sessions.values()) session.proc.kill("SIGKILL");
      }),
    );

    return TerminalService.of({
      list: Effect.sync(() => ({ sessions: [...sessions.values()].map(info) })),
      open,
      attach,
      write,
      resize,
      close,
    });
  }),
);
