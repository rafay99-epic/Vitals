import { describe, expect, test } from "bun:test";
import { strToU8, zipSync } from "fflate";

import { SHEET_ROWS, workbookOf } from "../src/lib/sheet.ts";

const xlsx = (sheets: ReadonlyArray<readonly [string, string]>, shared: ReadonlyArray<string>, styles = "") =>
  zipSync({
    "xl/workbook.xml": strToU8(`<workbook xmlns:r="r"><sheets>${sheets.map(([name], index) => `<sheet name="${name}" sheetId="${String(index + 1)}" r:id="rId${String(index + 1)}"/>`).join("")}</sheets></workbook>`),
    "xl/_rels/workbook.xml.rels": strToU8(`<Relationships>${sheets.map((_, index) => `<Relationship Id="rId${String(index + 1)}" Target="worksheets/sheet${String(index + 1)}.xml"/>`).join("")}</Relationships>`),
    "xl/sharedStrings.xml": strToU8(`<sst>${shared.map((text) => `<si>${text}</si>`).join("")}</sst>`),
    "xl/styles.xml": strToU8(styles),
    ...Object.fromEntries(sheets.map(([, xml], index) => [`xl/worksheets/sheet${String(index + 1)}.xml`, strToU8(`<worksheet><sheetData>${xml}</sheetData></worksheet>`)])),
  });

describe("sheet", () => {
  test("reads shared, inline, rich, boolean, number and date cells into their columns", () => {
    const styles = `<styleSheet><numFmts><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts><cellXfs><xf numFmtId="0"/><xf numFmtId="164"/></cellXfs></styleSheet>`;
    const book = workbookOf(
      xlsx(
        [
          ["Budget", `<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row><row r="3"><c r="A3"><v>0.30000000000000004</v></c><c r="B3" t="b"><v>1</v></c><c r="C3" s="1"><v>46322</v></c><c r="D3" t="inlineStr"><is><t>a &amp; b</t></is></c></row>`],
          ["Empty", ""],
        ],
        ["<t>Item</t>", '<r><t>Rich </t></r><r><t xml:space="preserve">text</t></r><rPh><t>skip</t></rPh>'],
        styles,
      ),
    );
    expect(book.names).toEqual(["Budget", "Empty"]);
    expect(book.sheet(0)).toEqual({ rows: [["Item", "", "Rich text"], [], ["0.3", "TRUE", "2026-10-27", "a & b"]], columns: 4, cut: false });
    expect(book.sheet(1)).toEqual({ rows: [], columns: 0, cut: false });
  });

  test("stops after SHEET_ROWS rows and says so", () => {
    const rows = Array.from({ length: SHEET_ROWS + 5 }, (_, index) => `<row r="${String(index + 1)}"><c r="A${String(index + 1)}"><v>${String(index)}</v></c></row>`).join("");
    const sheet = workbookOf(xlsx([["Big", rows]], [])).sheet(0);
    expect(sheet.rows).toHaveLength(SHEET_ROWS);
    expect(sheet.cut).toBe(true);
  });

  test("says what's wrong with a file that isn't a spreadsheet", () => {
    expect(() => workbookOf(strToU8("not a zip"))).toThrow("This isn't a spreadsheet Vitals can read");
  });
});
