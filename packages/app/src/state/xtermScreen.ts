import { Store } from "@vitals/client-runtime";
import type { TerminalSize } from "@vitals/contracts";
import "./xtermHost.ts";
import { type IBufferCell, Terminal } from "@xterm/headless";

import type { TerminalSink } from "./terminal.ts";

const FRAME_MS = 33;
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

export const PALETTE = ["#000000", "#ff4d6d", "#5cf2a6", "#f2ec6b", "#74d4ff", "#c8a8ff", "#63e6e2", "#d4d4d4", "#6b6b6b", "#ff6b8b", "#7dffbd", "#fff79a", "#9fe1ff", "#dcc6ff", "#8ff1ee", "#ffffff"] as const;
const CUBE = [0, 95, 135, 175, 215, 255];

const hex = (value: number): string => `#${value.toString(16).padStart(6, "0")}`;

const palette = (index: number): string => {
  if (index < 16) return PALETTE[index] ?? "#ffffff";
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

export const CURSOR_FG = "#000000";
export const CURSOR_BG = "#f2ec6b";

export class XtermScreen implements TerminalSink {
  readonly lines = new Store<ReadonlyArray<Line>>([]);
  private readonly term: Terminal;
  private readonly cell: IBufferCell;
  private frameTimer: ReturnType<typeof setTimeout> | null = null;
  private previous = new Map<string, Line>();

  constructor(size: TerminalSize, respond: (data: string) => void) {
    this.term = new Terminal({ cols: size.cols, rows: size.rows, scrollback: SCROLLBACK, allowProposedApi: true });
    this.cell = this.term.buffer.active.getNullCell();
    this.term.onData(respond);
  }

  reset(): void {
    this.term.reset();
    this.schedule();
  }

  write(data: string): void {
    this.term.write(data, () => this.schedule());
  }

  resize(size: TerminalSize): void {
    if (size.cols === this.term.cols && size.rows === this.term.rows) return;
    this.term.resize(size.cols, size.rows);
    this.schedule();
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
          const cursor = y === cursorRow && x === buffer.cursorX;
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
      const value = this.previous.get(key) ?? { key, runs };
      next.set(key, value);
      lines.push(value);
    }
    this.previous = next;
    this.lines.set(lines);
  }
}
