export type GlyphName = "chart" | "orders" | "ward" | "alarms" | "record";

export const GLYPH_PATHS: Record<GlyphName, string> = {
  chart: "M1 10 H8 L10 13 L14 2 L16 10 H25",
  orders: "M3 3 H5 M9 3 H23 M3 8 H5 M9 8 H23 M3 13 H5 M9 13 H17",
  ward: "M3 2 V14 M3 10 H23 V14 M6 7 H11",
  alarms: "M13 1.5 L23.5 14.5 H2.5 Z M13 6.5 V10",
  record: "M6 1 H20 V15 H6 Z M9 5 H17 M9 8 H17 M9 11 H14",
};

export const MARK_PATH = "M2 18 H12 L16 26 L24 4 L28 18 H46";

export const BEAT_OFF = "M1 14 H43";

export const BEAT_ON = "M1 14 H15 L19 18 L24 3 L28 14 H43";
