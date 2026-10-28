import { Canvas, PaintStyle, Path, Skia, type SkPath, StrokeCap, StrokeJoin } from "@shopify/react-native-skia";
import { Image, PixelRatio } from "react-native";

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
  text: "M5 6h14M5 10h14M5 14h10M5 18h6",
  image: `${box(3, 5, 18, 14, 2)}${circle(9, 10, 1.6)}M21 16l-5-5-8 8`,
  file: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5",
  folder: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
  copy: `${box(9, 9, 11, 11, 2)}M15 9V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h3`,
  send: "M12 19V5M6 11l6-6 6 6",
  share: "M12 3v12M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7",
  pin: "M9 4h6l-1 6 4 4H6l4-4zM12 14v6",
  trash: "M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3",
  mac: `${box(5, 5, 14, 10, 1.5)}M3 19h18`,
  phone: `${box(7, 3, 10, 18, 2)}M11 18h2`,
  down: "M12 4v12M7 11l5 5 5-5M5 20h14",
  video: `${box(3, 6, 13, 12, 2)}M16 10.5l5-3v9l-5-3`,
  android: `M6 18v-6a6 6 0 0 1 12 0v6zM8 5l1.6 2.4M16 5l-1.6 2.4${circle(9.5, 12, 0.4)}${circle(14.5, 12, 0.4)}`,
  files: "M9 3h6l4 4v10a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM15 3v4h4M4 8v11a3 3 0 0 0 3 3h8",
  terminal: `${box(3, 4, 18, 16, 2)}M7 9l3 3-3 3M12 15h5`,
  plus: "M12 5v14M5 12h14",
  keyboard: `${box(2, 6, 20, 12, 2)}M6 10h1M10 10h1M14 10h1M18 10h1M8 14h8`,
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

const DRAWN = new Map<string, string>();

/** The icon drawn once into a PNG data URI at the screen's pixel density, then reused. */
const drawn = (name: IconName, size: number, color: string, weight: number): string => {
  const key = `${name}:${String(size)}:${color}:${String(weight)}`;
  const known = DRAWN.get(key);
  if (known !== undefined) return known;
  const density = PixelRatio.get();
  const pixels = Math.ceil(size * density);
  const surface = Skia.Surface.Make(pixels, pixels);
  if (surface === null) return "";
  const paint = Skia.Paint();
  paint.setStyle(PaintStyle.Stroke);
  paint.setStrokeWidth(weight);
  paint.setStrokeJoin(StrokeJoin.Round);
  paint.setStrokeCap(StrokeCap.Round);
  paint.setColor(Skia.Color(color));
  paint.setAntiAlias(true);
  const canvas = surface.getCanvas();
  canvas.scale((size * density) / 24, (size * density) / 24);
  canvas.drawPath(pathOf(name), paint);
  surface.flush();
  const uri = `data:image/png;base64,${surface.makeImageSnapshot().encodeToBase64()}`;
  DRAWN.set(key, uri);
  return uri;
};

/**
 * The same icon as a plain image: drawn once, then each use is just a cached bitmap. For long lists, where
 * a live canvas per row costs JS and UI work on every scroll.
 */
export function StaticIcon({ name, size = 20, color = palette.ink, weight = 2 }: IconProps) {
  return <Image source={{ uri: drawn(name, size, color, weight) }} style={{ width: size, height: size }} accessibilityElementsHidden importantForAccessibility="no-hide-descendants" />;
}

export function Icon({ name, size = 20, color = palette.ink, weight = 2 }: IconProps) {
  const scale = size / 24;
  return (
    <Canvas style={{ width: size, height: size }} pointerEvents="none" accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      <Path path={pathOf(name)} style="stroke" strokeWidth={weight} color={color} strokeJoin="round" strokeCap="round" transform={[{ scale }]} />
    </Canvas>
  );
}
