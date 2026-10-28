import { lexer, type MarkedToken, type Tokens } from "marked";

const FENCE = /^\s*(```|~~~)/;

/**
 * MDX's `import`/`export` blocks, dropped: they're code for the site that renders the file, not text to
 * read. Like MDX itself, a block runs from its first line to the next blank line. Fenced code is kept.
 */
const withoutEsm = (text: string): string => {
  let fenced = false;
  let skipping = false;
  return text
    .split("\n")
    .filter((line) => {
      if (FENCE.test(line)) fenced = !fenced;
      if (fenced) return true;
      if (skipping) {
        skipping = line.trim() !== "";
        return false;
      }
      skipping = /^(import|export)\s/.test(line);
      return !skipping;
    })
    .join("\n");
};

/**
 * A Markdown or MDX file as its top-level blocks. Front matter becomes a code block so it still shows.
 * JSX stays in as raw `html` blocks.
 */
export const markdownBlocks = (text: string, mdx: boolean): ReadonlyArray<MarkedToken> => {
  const front = /^---\n([\s\S]*?)\n---(?:\n|$)/.exec(text);
  const body = front === null ? text : text.slice(front[0].length);
  // marked only makes its own tokens when no extensions are added, as here.
  const blocks = lexer(mdx ? withoutEsm(body) : body) as ReadonlyArray<MarkedToken>;
  const shown = blocks.filter((block) => block.type !== "space" && block.type !== "def");
  if (front === null) return shown;
  const matter: Tokens.Code = { type: "code", raw: front[0], lang: "yaml", text: front[1] ?? "" };
  return [matter, ...shown];
};
