import { channels } from "../theme.ts";
import { GLYPH_PATHS, type GlyphName, MARK_PATH } from "./glyphPaths.ts";

export type { GlyphName } from "./glyphPaths.ts";

export function Glyph({ name, color }: { readonly name: GlyphName; readonly color: string }) {
  return (
    <svg width={26} height={16} viewBox="0 0 26 16" aria-hidden style={{ display: "block" }}>
      <path d={GLYPH_PATHS[name]} fill="none" stroke={color} strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  );
}

export function Mark({ width = 42 }: { readonly width?: number }) {
  return (
    <svg width={width} height={(width / 48) * 32} viewBox="0 0 48 32" role="img" aria-label="Vitals" style={{ display: "block" }}>
      <path d={MARK_PATH} fill="none" stroke={channels.pulse.color} strokeWidth={2.6} strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  );
}
