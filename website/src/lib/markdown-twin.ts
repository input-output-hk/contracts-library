/**
 * Serves a canonical document from `docs/` as plain Markdown.
 *
 * The llms.txt proposal (https://llmstxt.org) asks for a Markdown version of
 * each page at the same URL with `.md` appended, so agents can fetch text
 * instead of parsing HTML. These files are the raw canonical documents with two
 * differences: their relative links are resolved to site or GitHub URLs, and
 * nothing else is touched — the H1 stays, unlike the HTML render where
 * Starlight supplies the title.
 */

import { readFile } from "node:fs/promises";
import path from "node:path";

import { type DocRef, docRouteMap, REPO_BRANCH, REPO_URL } from "./manifest";
import { resolveRepoLink } from "./remark-rewrite-links";
import { repoRoot } from "./repo";

/** `](target)` or `](target "title")` — the two inline link shapes in `docs/`. */
const INLINE_LINK = /\]\(([^)\s]+)((?:\s+"[^"]*")?)\)/g;

/** A line that opens or closes a fenced code block. */
const FENCE = /^\s*(```|~~~)/;

function rewriteLinks(source: string, sourceFile: string): string {
  const options = {
    repoRoot,
    routes: docRouteMap(),
    repoUrl: REPO_URL,
    branch: REPO_BRANCH,
    routeSuffix: ".md",
  };

  let inFence = false;
  return source
    .split("\n")
    .map((line) => {
      if (FENCE.test(line)) {
        inFence = !inFence;
        return line;
      }
      // Fenced samples (Aiken, transaction shapes) must be copied verbatim.
      if (inFence) return line;
      return line.replace(INLINE_LINK, (match, url: string, title: string) => {
        const resolved = resolveRepoLink(url, sourceFile, options);
        return resolved ? `](${resolved}${title})` : match;
      });
    })
    .join("\n");
}

/** Read `docs/<file>` and return it ready to serve as a Markdown twin. */
export async function renderMarkdownTwin(doc: DocRef): Promise<string> {
  const sourceFile = path.join(repoRoot, "docs", doc.file);
  const source = await readFile(sourceFile, "utf8");
  return rewriteLinks(source, sourceFile);
}
