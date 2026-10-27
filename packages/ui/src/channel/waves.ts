import { Skia, type SkPath } from "@shopify/react-native-skia";

import type { Wave } from "../theme.ts";

export interface WaveInput {
  readonly values: ReadonlyArray<number>;
  readonly width: number;
  readonly height: number;
  readonly min: number;
  readonly max: number | null;
  readonly beats: number;
}

export interface Pen {
  moveTo(x: number, y: number): unknown;
  lineTo(x: number, y: number): unknown;
  quadTo(x1: number, y1: number, x2: number, y2: number): unknown;
  cubicTo(x1: number, y1: number, x2: number, y2: number, x3: number, y3: number): unknown;
}

type Draw = (builder: Pen, levels: ReadonlyArray<number>, width: number, height: number) => void;

const noise = (index: number): number => {
  "worklet";
  const x = Math.sin(index * 12.9898 + 78.233) * 43_758.5453;
  return x - Math.floor(x) - 0.5;
};

const ecg: Draw = (b, levels, w, h) => {
  "worklet";
  const bw = w / levels.length;
  const base = h * 0.66;
  b.moveTo(0, base);
  levels.forEach((level, i) => {
    const x = i * bw;
    const amp = h * 0.12 + h * 0.5 * level;
    b.lineTo(x + bw * 0.3, base);
    b.quadTo(x + bw * 0.36, base - h * 0.08, x + bw * 0.42, base);
    b.lineTo(x + bw * 0.5, base + h * 0.08);
    b.lineTo(x + bw * 0.56, base - amp);
    b.lineTo(x + bw * 0.62, base + h * 0.16);
    b.lineTo(x + bw * 0.68, base);
    b.quadTo(x + bw * 0.8, base - h * 0.14, x + bw * 0.92, base);
    b.lineTo(x + bw, base);
  });
};

const art: Draw = (b, levels, w, h) => {
  "worklet";
  const bw = w / levels.length;
  const base = h * 0.82;
  b.moveTo(0, base);
  levels.forEach((level, i) => {
    const x = i * bw;
    const amp = h * 0.25 + h * 0.5 * level;
    b.lineTo(x + bw * 0.12, base);
    b.cubicTo(x + bw * 0.2, base - amp, x + bw * 0.26, base - amp, x + bw * 0.34, base - amp * 0.72);
    b.lineTo(x + bw * 0.42, base - amp * 0.6);
    b.quadTo(x + bw * 0.48, base - amp * 0.68, x + bw * 0.54, base - amp * 0.5);
    b.quadTo(x + bw * 0.8, base - amp * 0.08, x + bw, base);
  });
};

const sine: Draw = (b, levels, w, h) => {
  "worklet";
  const cw = w / levels.length;
  const mid = h * 0.55;
  b.moveTo(0, mid);
  levels.forEach((level, i) => {
    const x = i * cw;
    const amp = h * 0.42 * Math.max(0.08, level);
    b.cubicTo(x + cw * 0.25, mid - amp, x + cw * 0.45, mid - amp, x + cw * 0.6, mid);
    b.cubicTo(x + cw * 0.75, mid + amp * 0.35, x + cw * 0.9, mid + amp * 0.35, x + cw, mid);
  });
};

const pleth: Draw = (b, levels, w, h) => {
  "worklet";
  const cw = w / levels.length;
  const base = h * 0.85;
  b.moveTo(0, base);
  levels.forEach((level, i) => {
    const x = i * cw;
    const amp = h * 0.2 + h * 0.5 * level;
    b.cubicTo(x + cw * 0.15, base, x + cw * 0.2, base - amp, x + cw * 0.35, base - amp);
    b.cubicTo(x + cw * 0.55, base - amp, x + cw * 0.7, base - amp * 0.2, x + cw, base);
  });
};

const eeg: Draw = (b, levels, w, h) => {
  "worklet";
  const steps = levels.length * 6;
  const sw = w / steps;
  const mid = h * 0.55;
  b.moveTo(0, mid);
  for (let i = 1; i <= steps; i += 1) {
    const level = levels[Math.min(levels.length - 1, Math.floor(i / 6))] ?? 0;
    b.lineTo(i * sw, mid + noise(i + levels.length) * 2 * h * 0.45 * Math.max(0.1, level));
  }
};

const step: Draw = (b, levels, w, h) => {
  "worklet";
  const sw = w / levels.length;
  levels.forEach((level, i) => {
    const y = h * 0.9 - h * 0.75 * level;
    if (i === 0) b.moveTo(0, y);
    else b.lineTo(i * sw, y);
    b.lineTo((i + 1) * sw, y);
  });
};

const bars: Draw = (b, levels, w, h) => {
  "worklet";
  const sw = w / levels.length;
  const base = h * 0.92;
  levels.forEach((level, i) => {
    b.moveTo(i * sw + sw / 2, base);
    b.lineTo(i * sw + sw / 2, base - Math.max(2, h * 0.8 * level));
  });
};

const draw = (wave: Wave): Draw => {
  "worklet";
  switch (wave) {
    case "ecg":
      return ecg;
    case "art":
      return art;
    case "wave":
      return sine;
    case "pleth":
      return pleth;
    case "eeg":
      return eeg;
    case "step":
      return step;
    case "bars":
      return bars;
  }
};

export const drawWave = (pen: Pen, wave: Wave, input: WaveInput): void => {
  "worklet";
  const { values, width, height, min, max, beats } = input;
  if (width === 0 || values.length === 0) return;
  const window = values.slice(-beats);
  let top = max ?? min;
  if (max === null) for (const value of window) top = Math.max(top, value);
  const span = Math.max(top - min, 1e-6);
  const levels = window.map((value) => Math.min(1, Math.max(0, (value - min) / span)));
  draw(wave)(pen, levels, width, height);
};

export const peakOf = (series: ReadonlyArray<ReadonlyArray<number>>, beats: number, min: number): number => {
  "worklet";
  let top = min;
  for (const values of series) for (const value of values.slice(-beats)) top = Math.max(top, value);
  return top;
};

export const wavePath = (wave: Wave, input: WaveInput): SkPath => {
  "worklet";
  const builder = Skia.PathBuilder.Make();
  drawWave(builder, wave, input);
  return builder.build();
};

export const flatPath = (width: number, height: number): SkPath => {
  "worklet";
  return Skia.PathBuilder.Make().moveTo(0, height * 0.66).lineTo(width, height * 0.66).build();
};
