import { strFromU8, unzipSync } from "fflate";

/** Spreadsheets bigger than this are left to another app. Everything is unpacked in memory. */
export const SHEET_BYTES = 20 * 1024 * 1024;
/** Rows and columns shown per sheet: enough to read it, few enough to stay quick. */
export const SHEET_ROWS = 2_000;
const SHEET_COLUMNS = 60;

export interface SheetRows {
  readonly rows: ReadonlyArray<ReadonlyArray<string>>;
  readonly columns: number;
  /** More rows or columns than shown. */
  readonly cut: boolean;
}

export interface Workbook {
  readonly names: ReadonlyArray<string>;
  /** One sheet's cells as text, read the first time it's asked for. */
  readonly sheet: (index: number) => SheetRows;
}

const ENTITIES: Readonly<Record<string, string>> = { lt: "<", gt: ">", amp: "&", quot: '"', apos: "'", nbsp: "\u00a0" };

/** `&amp;`, `&#38;` and `&#x26;` as `&`. Shared with the Markdown viewer. */
export const unescape = (text: string): string =>
  text.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (whole, name: string) => {
    if (!name.startsWith("#")) return ENTITIES[name] ?? whole;
    const code = name[1] === "x" || name[1] === "X" ? Number.parseInt(name.slice(2), 16) : Number.parseInt(name.slice(1), 10);
    return code <= 0x10_ffff ? String.fromCodePoint(code) : whole;
  });

/** A tag's attributes, by name without its namespace. */
const attributes = (tag: string): ReadonlyMap<string, string> => new Map([...tag.matchAll(/([\w:]+)="([^"]*)"/g)].map(([, name = "", value = ""]) => [name.slice(name.indexOf(":") + 1), unescape(value)]));

/** Every `<t>` run inside a rich string, joined. Phonetic hints are skipped. */
const runs = (xml: string): string => unescape([...xml.replace(/<rPh\b[\s\S]*?<\/rPh>/g, "").matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(([, text = ""]) => text).join(""));

/** "AB" to 27. */
const columnOf = (ref: string): number => {
  let index = 0;
  for (const letter of ref.replace(/\d+$/, "").toUpperCase()) index = index * 26 + letter.charCodeAt(0) - 64;
  return index - 1;
};

/** Built-in number formats that are dates or times. */
const DATE_FORMATS = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]);

/** Which cell styles show dates: their number format is a built-in date one, or a custom one with day, month or year in it. */
const dateStyles = (xml: string | undefined): ReadonlySet<number> => {
  if (xml === undefined) return new Set();
  const custom = new Map([...xml.matchAll(/<numFmt\b[^>]*>/g)].map(([tag]) => attributes(tag)).map((attrs) => [Number(attrs.get("numFmtId")), attrs.get("formatCode") ?? ""] as const));
  const isDate = (id: number): boolean => DATE_FORMATS.has(id) || /[dmy]/i.test((custom.get(id) ?? "").replace(/"[^"]*"|\[[^\]]*\]/g, ""));
  const xfs = /<cellXfs\b[\s\S]*?<\/cellXfs>/.exec(xml)?.[0] ?? "";
  return new Set([...xfs.matchAll(/<xf\b[^>]*>/g)].flatMap(([tag], index) => (isDate(Number(attributes(tag).get("numFmtId") ?? 0)) ? [index] : [])));
};

/** An Excel day count as "2026-10-27", with the time when there is one. */
const dateOf = (serial: number): string => {
  const iso = new Date(Math.round((serial - 25_569) * 86_400_000)).toISOString();
  return serial % 1 === 0 ? iso.slice(0, 10) : `${iso.slice(0, 10)} ${iso.slice(11, 16)}`;
};

/** A stored number as a person would type it: no floating point noise. */
const numberOf = (raw: string): string => {
  const value = Number(raw);
  return Number.isFinite(value) ? String(Number.parseFloat(value.toPrecision(12))) : raw;
};

const readRows = (xml: string, shared: ReadonlyArray<string>, dates: ReadonlySet<number>): SheetRows => {
  const rows: Array<Array<string>> = [];
  let columns = 0;
  let cut = false;
  for (const [, rowTag = "", body = ""] of xml.matchAll(/<row\b([^>]*?)(?:\/>|>([\s\S]*?)<\/row>)/g)) {
    const at = Number(attributes(rowTag).get("r") ?? rows.length + 1) - 1;
    if (at >= SHEET_ROWS) {
      cut = true;
      break;
    }
    const row: Array<string> = [];
    for (const [, cellTag = "", inner = ""] of body.matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attrs = attributes(cellTag);
      const column = attrs.has("r") ? columnOf(attrs.get("r") ?? "A") : row.length;
      if (column >= SHEET_COLUMNS) {
        cut = true;
        continue;
      }
      const value = /<v>([\s\S]*?)<\/v>/.exec(inner)?.[1];
      const type = attrs.get("t") ?? "n";
      let text: string;
      if (type === "s") text = shared[Number(value)] ?? "";
      else if (type === "inlineStr") text = runs(inner);
      else if (type === "b") text = value === "1" ? "TRUE" : "FALSE";
      else if (value === undefined) text = "";
      else if (type === "n" && dates.has(Number(attrs.get("s") ?? -1))) text = dateOf(Number(value));
      else if (type === "n") text = numberOf(value);
      else text = unescape(value);
      row[column] = text;
    }
    while (rows.length < at) rows.push([]);
    rows[at] = Array.from(row, (cell) => cell ?? "");
    columns = Math.max(columns, row.length);
  }
  while (rows.length > 0 && rows.at(-1)?.every((cell) => cell === "") === true) rows.pop();
  return { rows, columns, cut };
};

/** An .xlsx's bytes as a workbook. Sheets are read on demand, `SHEET_ROWS` rows at most. */
export const workbookOf = (bytes: Uint8Array): Workbook => {
  let files: Record<string, Uint8Array>;
  try {
    files = unzipSync(bytes, { filter: (entry) => (entry.name.startsWith("xl/") && entry.name.endsWith(".xml")) || entry.name.endsWith(".rels") });
  } catch {
    throw new Error("This isn't a spreadsheet Vitals can read");
  }
  const text = (name: string): string | undefined => {
    const found = files[name];
    return found === undefined ? undefined : strFromU8(found);
  };
  const workbook = text("xl/workbook.xml");
  if (workbook === undefined) throw new Error("This isn't a spreadsheet Vitals can read");
  const targets = new Map(
    [...(text("xl/_rels/workbook.xml.rels") ?? "").matchAll(/<Relationship\b[^>]*>/g)].map(([tag]) => {
      const attrs = attributes(tag);
      const target = attrs.get("Target") ?? "";
      return [attrs.get("Id") ?? "", target.startsWith("/") ? target.slice(1) : `xl/${target}`] as const;
    }),
  );
  const sheets = [...workbook.matchAll(/<sheet\b[^>]*>/g)].map(([tag]) => {
    const attrs = attributes(tag);
    return { name: attrs.get("name") ?? "Sheet", path: targets.get(attrs.get("id") ?? "") ?? "" };
  });
  const shared = [...(text("xl/sharedStrings.xml") ?? "").matchAll(/<si>([\s\S]*?)<\/si>/g)].map(([, item = ""]) => runs(item));
  const dates = dateStyles(text("xl/styles.xml"));
  const read = new Map<number, SheetRows>();
  return {
    names: sheets.map((sheet) => sheet.name),
    sheet: (index) => {
      const known = read.get(index);
      if (known !== undefined) return known;
      const xml = text(sheets[index]?.path ?? "");
      const rows = xml === undefined ? { rows: [], columns: 0, cut: false } : readRows(xml, shared, dates);
      read.set(index, rows);
      return rows;
    },
  };
};
