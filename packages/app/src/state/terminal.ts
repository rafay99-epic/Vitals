import type { Connection } from "@vitals/client-runtime";
import { Store } from "@vitals/client-runtime";
import type { TerminalEvent, TerminalId, TerminalInfo, TerminalSize } from "@vitals/contracts";
import { type IBufferCell, Terminal } from "@xterm/headless";

const FRAME_MS = 33;
const INPUT_MS = 8;
const SCROLLBACK = 2_000;

export interface Run {
  readonly col: number;
  readonly text: string;
  readonly fg: string | null;
  readonly bg: string | null;
  readonly bold: boolean;
  readonly dim: boolean;
  readonly italic: boolean;
  readonly underline: boolean;
}

export interface Line {
  readonly key: string;
  readonly runs: ReadonlyArray<Run>;
}

export interface Frame {
  readonly lines: ReadonlyArray<Line>;
  readonly exited: boolean;
  readonly exitCode: number | null;
  readonly attached: boolean;
}

const BASE16 = ["#000000", "#ff4d6d", "#5cf2a6", "#f2ec6b", "#74d4ff", "#c8a8ff", "#63e6e2", "#d4d4d4", "#6b6b6b", "#ff6b8b", "#7dffbd", "#fff79a", "#9fe1ff", "#dcc6ff", "#8ff1ee", "#ffffff"];
const CUBE = [0, 95, 135, 175, 215, 255];

const hex = (value: number): string => `#${value.toString(16).padStart(6, "0")}`;

const palette = (index: number): string => {
  if (index < 16) return BASE16[index] ?? "#ffffff";
  if (index >= 232) {
    const level = 8 + (index - 232) * 10;
    return hex((level << 16) | (level << 8) | level);
  }
  const cube = index - 16;
  return hex(((CUBE[Math.floor(cube / 36)] ?? 0) << 16) | ((CUBE[Math.floor(cube / 6) % 6] ?? 0) << 8) | (CUBE[cube % 6] ?? 0));
};

const fgOf = (cell: IBufferCell): string | null => (cell.isFgDefault() ? null : cell.isFgRGB() ? hex(cell.getFgColor()) : palette(cell.getFgColor()));
const bgOf = (cell: IBufferCell): string | null => (cell.isBgDefault() ? null : cell.isBgRGB() ? hex(cell.getBgColor()) : palette(cell.getBgColor()));

const sameStyle = (run: Run, fg: string | null, bg: string | null, cell: IBufferCell): boolean =>
  run.fg === fg && run.bg === bg && run.bold === (cell.isBold() !== 0) && run.dim === (cell.isDim() !== 0) && run.italic === (cell.isItalic() !== 0) && run.underline === (cell.isUnderline() !== 0);

const CURSOR_FG = "#000000";
const CURSOR_BG = "#f2ec6b";

export class TerminalSession {
  readonly frame = new Store<Frame>({ lines: [], exited: false, exitCode: null, attached: false });
  readonly info = new Store<TerminalInfo | null>(null);
  private readonly connection: Connection;
  private readonly id: TerminalId;
  private readonly term: Terminal;
  private readonly cell: IBufferCell;
  private stop: (() => void) | null = null;
  private frameTimer: ReturnType<typeof setTimeout> | null = null;
  private inputTimer: ReturnType<typeof setTimeout> | null = null;
  private pendingInput = "";
  private previous = new Map<string, Line>();
  private exited = false;
  private exitCode: number | null = null;

  constructor(connection: Connection, id: TerminalId, size: TerminalSize) {
    this.connection = connection;
    this.id = id;
    this.term = new Terminal({ cols: size.cols, rows: size.rows, scrollback: SCROLLBACK, allowProposedApi: true });
    this.cell = this.term.buffer.active.getNullCell();
    this.term.onData((data) => this.send(data));
  }

  attach(): void {
    if (this.stop !== null) return;
    this.stop = this.connection.watch(
      (client) => client["terminal.attach"]({ id: this.id, cols: this.term.cols, rows: this.term.rows }),
      (event) => this.apply(event),
    );
  }

  detach(): void {
    this.stop?.();
    this.stop = null;
    this.frame.update((frame) => ({ ...frame, attached: false }));
  }

  input(data: string): void {
    if (this.exited || data.length === 0) return;
    this.pendingInput += data;
    this.inputTimer ??= setTimeout(() => this.flushInput(), INPUT_MS);
  }

  resize(size: TerminalSize): void {
    if (size.cols === this.term.cols && size.rows === this.term.rows) return;
    this.term.resize(size.cols, size.rows);
    this.schedule();
    void this.connection.call((client) => client["terminal.resize"]({ id: this.id, cols: size.cols, rows: size.rows }));
  }

  dispose(): void {
    this.detach();
    if (this.frameTimer !== null) clearTimeout(this.frameTimer);
    if (this.inputTimer !== null) clearTimeout(this.inputTimer);
    this.term.dispose();
  }

  private send(data: string): void {
    this.pendingInput += data;
    this.inputTimer ??= setTimeout(() => this.flushInput(), INPUT_MS);
  }

  private flushInput(): void {
    this.inputTimer = null;
    const data = this.pendingInput;
    this.pendingInput = "";
    if (data.length > 0) void this.connection.call((client) => client["terminal.write"]({ id: this.id, data }));
  }

  private apply(event: TerminalEvent): void {
    switch (event._tag) {
      case "Snapshot":
        this.info.set(event.info);
        this.exited = !event.info.running;
        this.exitCode = event.info.exitCode;
        this.term.reset();
        this.term.write(event.history, () => this.schedule());
        this.frame.update((frame) => ({ ...frame, attached: true }));
        return;
      case "Output":
        this.term.write(event.data, () => this.schedule());
        return;
      case "Exited":
        this.exited = true;
        this.exitCode = event.code;
        this.schedule();
        return;
    }
  }

  private schedule(): void {
    this.frameTimer ??= setTimeout(() => {
      this.frameTimer = null;
      this.render();
    }, FRAME_MS);
  }

  private render(): void {
    const buffer = this.term.buffer.active;
    const top = buffer.viewportY;
    const cursorRow = buffer.baseY + buffer.cursorY;
    const next = new Map<string, Line>();
    const lines: Array<Line> = [];
    for (let row = 0; row < this.term.rows; row += 1) {
      const y = top + row;
      const line = buffer.getLine(y);
      const runs: Array<Run> = [];
      let signature = "";
      if (line !== undefined) {
        for (let x = 0; x < this.term.cols; x += 1) {
          const cell = line.getCell(x, this.cell);
          if (cell === undefined || cell.getWidth() === 0) continue;
          const cursor = !this.exited && y === cursorRow && x === buffer.cursorX;
          const inverse = cell.isInverse() !== 0;
          let fg = fgOf(cell);
          let bg = bgOf(cell);
          if (inverse) [fg, bg] = [bg ?? "#000000", fg ?? "#ffffff"];
          if (cursor) [fg, bg] = [CURSOR_FG, CURSOR_BG];
          const chars = cell.getChars() || " ";
          const last = runs.at(-1);
          if (last !== undefined && !cursor && sameStyle(last, fg, bg, cell) && !(y === cursorRow && x === buffer.cursorX + 1)) {
            runs[runs.length - 1] = { ...last, text: last.text + chars };
          } else {
            runs.push({ col: x, text: chars, fg, bg, bold: cell.isBold() !== 0, dim: cell.isDim() !== 0, italic: cell.isItalic() !== 0, underline: cell.isUnderline() !== 0 });
          }
        }
      }
      const tail = runs.at(-1);
      if (tail !== undefined && tail.bg === null) runs[runs.length - 1] = { ...tail, text: tail.text.trimEnd() };
      for (const run of runs) signature += `${run.fg ?? ""}|${run.bg ?? ""}|${run.bold ? 1 : 0}${run.dim ? 1 : 0}${run.italic ? 1 : 0}${run.underline ? 1 : 0}|${run.text}\u0000`;
      const key = `${String(row)}:${signature}`;
      const reused = this.previous.get(key);
      const value = reused ?? { key, runs };
      next.set(key, value);
      lines.push(value);
    }
    this.previous = next;
    this.frame.set({ lines, exited: this.exited, exitCode: this.exitCode, attached: this.stop !== null });
  }
}

export class MacTerminals {
  readonly sessions = new Store<ReadonlyArray<TerminalInfo>>([]);
  private readonly connection: Connection;
  private readonly open = new Map<string, TerminalSession>();

  constructor(connection: Connection) {
    this.connection = connection;
  }

  async refresh(): Promise<void> {
    const result = await this.connection.call((client) => client["terminal.list"]({}));
    if (result.ok) this.sessions.set(result.value.sessions);
  }

  async start(size: TerminalSize): Promise<TerminalInfo | string> {
    const result = await this.connection.call((client) => client["terminal.open"](size));
    if (!result.ok) return result.error.message;
    this.sessions.update((sessions) => [...sessions, result.value]);
    return result.value;
  }

  session(id: TerminalId, size: TerminalSize): TerminalSession {
    const existing = this.open.get(id);
    if (existing !== undefined) return existing;
    const created = new TerminalSession(this.connection, id, size);
    this.open.set(id, created);
    return created;
  }

  async end(id: TerminalId): Promise<void> {
    await this.connection.call((client) => client["terminal.close"]({ id }));
    this.open.get(id)?.dispose();
    this.open.delete(id);
    this.sessions.update((sessions) => sessions.filter((session) => session.id !== id));
  }

  dispose(): void {
    for (const session of this.open.values()) session.dispose();
    this.open.clear();
  }
}
