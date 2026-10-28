import { describe, expect, test } from "bun:test";

import { markdownBlocks } from "../src/lib/markdown.ts";

describe("markdown", () => {
  test("shows front matter as a code block before the text", () => {
    const blocks = markdownBlocks("---\ntitle: Hi\n---\n# Hello\n\nText", false);
    expect(blocks.map((block) => block.type)).toEqual(["code", "heading", "paragraph"]);
    expect(blocks[0]).toMatchObject({ type: "code", lang: "yaml", text: "title: Hi" });
  });

  test("drops MDX import and export blocks but keeps them inside code and in plain Markdown", () => {
    const text = 'import { Chart } from "./chart"\nimport X from "x"\n\nexport const meta = {\n  a: 1,\n}\n\n# Title\n\n```js\nimport y from "y"\n```\n\n<Chart />';
    expect(markdownBlocks(text, true).map((block) => block.type)).toEqual(["heading", "code", "html"]);
    expect(markdownBlocks(text, true)[1]).toMatchObject({ text: 'import y from "y"' });
    expect(markdownBlocks(text, false)[0]?.type).toBe("paragraph");
  });
});
