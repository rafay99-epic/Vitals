import type { Pen } from "./waves.ts";

const n = (value: number): string => value.toFixed(1);

export class SvgPen implements Pen {
  private parts: Array<string> = [];

  moveTo(x: number, y: number): this {
    this.parts.push(`M${n(x)} ${n(y)}`);
    return this;
  }

  lineTo(x: number, y: number): this {
    this.parts.push(`L${n(x)} ${n(y)}`);
    return this;
  }

  quadTo(x1: number, y1: number, x2: number, y2: number): this {
    this.parts.push(`Q${n(x1)} ${n(y1)} ${n(x2)} ${n(y2)}`);
    return this;
  }

  cubicTo(x1: number, y1: number, x2: number, y2: number, x3: number, y3: number): this {
    this.parts.push(`C${n(x1)} ${n(y1)} ${n(x2)} ${n(y2)} ${n(x3)} ${n(y3)}`);
    return this;
  }

  toString(): string {
    return this.parts.join(" ");
  }
}
