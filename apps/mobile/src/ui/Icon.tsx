import { Canvas, Path, Skia, type SkPath } from "@shopify/react-native-skia";

import { color as palette } from "./tokens.ts";

const circle = (cx: number, cy: number, r: number): string => `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0`;

const box = (x: number, y: number, w: number, h: number, r: number): string =>
  `M${x + r} ${y}h${w - 2 * r}a${r} ${r} 0 0 1 ${r} ${r}v${h - 2 * r}a${r} ${r} 0 0 1 ${-r} ${r}h${-(w - 2 * r)}a${r} ${r} 0 0 1 ${-r} ${-r}v${-(h - 2 * r)}a${r} ${r} 0 0 1 ${r} ${-r}z`;

/** Stroke icons drawn on a 24-unit grid. */
const PATHS = {
  power: "M12 3v8M6.4 6.6a8 8 0 1 0 11.2 0",
  moon: "M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z",
  lock: `${box(5, 11, 14, 9, 2)}M8 11V8a4 4 0 0 1 8 0v3`,
  restart: "M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5",
  screen: `${box(3, 4, 18, 12, 2)}M9 20h6`,
  logout: "M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M10 16l-4-4 4-4M6 12h10",
  home: "M4 11l8-7 8 7v9h-5v-6H9v6H4z",
  apps: `${box(4, 4, 6.5, 6.5, 1.5)}${box(13.5, 4, 6.5, 6.5, 1.5)}${box(4, 13.5, 6.5, 6.5, 1.5)}${box(13.5, 13.5, 6.5, 6.5, 1.5)}`,
  control: `M5 7h1.5M11.5 7H19M5 17h7.5M17.5 17H19${circle(9, 7, 2.5)}${circle(15, 17, 2.5)}`,
  bell: "M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0",
  gear: `${circle(12, 12, 3)}M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1`,
  search: `${circle(11, 11, 6.5)}M16 16l4 4`,
  pause: "M9 5v14M15 5v14",
  play: "M8 5l11 7-11 7z",
  slow: "M4 18a8 8 0 0 1 16 0M12 18l-4-5",
  sun: `${circle(12, 12, 4)}M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4`,
  sound: "M4 10v4h4l5 4V6L8 10zM16 9a4 4 0 0 1 0 6",
  clipboard: `${box(6, 5, 12, 15, 2)}M9 5V3h6v2`,
  link: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1",
  ping: `${circle(12, 12, 2)}M7 7a7 7 0 0 0 0 10M17 7a7 7 0 0 1 0 10`,
  chevron: "M9 6l6 6-6 6",
  back: "M15 6l-6 6 6 6",
  check: "M5 12l5 5L19 7",
  close: "M6 6l12 12M18 6L6 18",
  eye: `M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z${circle(12, 12, 3)}`,
  stop: box(6, 6, 12, 12, 2),
} as const;

export type IconName = keyof typeof PATHS;

const parse = (d: string): SkPath => Skia.Path.MakeFromSVGString(d) ?? Skia.PathBuilder.Make().build();

const CACHE = new Map<IconName, SkPath>();
const pathOf = (name: IconName): SkPath => {
  const known = CACHE.get(name);
  if (known !== undefined) return known;
  const parsed = parse(PATHS[name]);
  CACHE.set(name, parsed);
  return parsed;
};

export interface IconProps {
  readonly name: IconName;
  readonly size?: number;
  readonly color?: string;
  readonly weight?: number;
}

export function Icon({ name, size = 20, color = palette.ink, weight = 2 }: IconProps) {
  const scale = size / 24;
  return (
    <Canvas style={{ width: size, height: size }} pointerEvents="none" accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      <Path path={pathOf(name)} style="stroke" strokeWidth={weight} color={color} strokeJoin="round" strokeCap="round" transform={[{ scale }]} />
    </Canvas>
  );
}
