import { Canvas, Path, Skia, type SkPath } from "@shopify/react-native-skia";

import { channels } from "../theme.ts";
import { GLYPH_PATHS, type GlyphName, MARK_PATH } from "./glyphPaths.ts";

export type { GlyphName } from "./glyphPaths.ts";

const svg = (d: string): SkPath => Skia.Path.MakeFromSVGString(d) ?? Skia.PathBuilder.Make().build();

const GLYPHS: Record<GlyphName, SkPath> = {
  chart: svg(GLYPH_PATHS.chart),
  orders: svg(GLYPH_PATHS.orders),
  ward: svg(GLYPH_PATHS.ward),
  alarms: svg(GLYPH_PATHS.alarms),
  record: svg(GLYPH_PATHS.record),
};

const MARK = svg(MARK_PATH);

export function Glyph({ name, color }: { readonly name: GlyphName; readonly color: string }) {
  return (
    <Canvas style={{ width: 26, height: 16 }}>
      <Path path={GLYPHS[name]} style="stroke" strokeWidth={1.5} color={color} strokeJoin="round" strokeCap="round" />
    </Canvas>
  );
}

export function Mark({ width = 42 }: { readonly width?: number }) {
  const scale = width / 48;
  return (
    <Canvas style={{ width, height: 32 * scale }} accessibilityLabel="Vitals">
      <Path path={MARK} style="stroke" strokeWidth={2.6} color={channels.pulse.color} strokeJoin="round" strokeCap="round" transform={[{ scale }]} />
    </Canvas>
  );
}
