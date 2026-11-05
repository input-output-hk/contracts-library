#!/usr/bin/env node
/**
 * Verifies the generated `llms.txt` against the format at https://llmstxt.org
 * and checks that every link it contains resolves.
 *
 *     npm run build && npm run check:llms
 *
 * The check runs on `dist/`, so it catches the two failures that matter:
 * a malformed file (agents cannot parse it) and a link to a page or repository
 * path that no longer exists (agents cannot follow it).
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SITE = "https://contracts-library.io";
const REPO_URL = "https://github.com/input-output-hk/contracts-library";

const websiteRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const repoRoot = path.resolve(websiteRoot, "..");
const dist = path.resolve(websiteRoot, process.argv[2] ?? "dist");
const llmsPath = path.join(dist, "llms.txt");

const problems = [];
const fail = (message) => problems.push(message);
const isFile = (p) => existsSync(p) && statSync(p).isFile();

if (!isFile(llmsPath)) {
  console.error(`✗ ${path.relative(websiteRoot, llmsPath)} does not exist.`);
  console.error("  Run `npm run build` first.");
  process.exit(1);
}

const source = readFileSync(llmsPath, "utf8");
const lines = source.split("\n");
const content = lines.filter((line) => line.trim() !== "");

// --- Format ---------------------------------------------------------------

if (!content[0]?.startsWith("# ")) {
  fail("the first non-empty line must be an H1 (`# Title`)");
}
if (!content[1]?.startsWith("> ")) {
  fail("the line after the H1 must be a blockquote summary (`> ...`)");
}
if (content.filter((line) => /^# [^#]/.test(line)).length !== 1) {
  fail("the file must contain exactly one H1");
}

const firstSection = content.findIndex((line) => line.startsWith("## "));
if (firstSection === -1) {
  fail("the file must contain at least one `## ` section listing links");
} else {
  const sections = [];
  for (const [index, line] of content.entries()) {
    if (index < firstSection) continue;
    if (line.startsWith("## ")) {
      sections.push({ title: line.slice(3), items: 0 });
    } else if (line.startsWith("- [")) {
      sections.at(-1).items += 1;
    } else {
      fail(
        `only link items are allowed inside the file list sections, found: ${line}`,
      );
    }
  }
  for (const section of sections) {
    if (section.items === 0) fail(`section "## ${section.title}" has no links`);
  }
}

// --- Links ----------------------------------------------------------------

const linkPattern = /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g;
const checked = [];
for (const match of source.matchAll(linkPattern)) {
  const [, title, url] = match;
  checked.push(url);

  if (url.startsWith("http://")) {
    fail(`link "${title}" uses http://; use https://`);
    continue;
  }

  if (url.startsWith(SITE)) {
    const pathname = decodeURIComponent(new URL(url).pathname);
    const target = path.join(dist, pathname);

    if (pathname.endsWith(".md")) {
      if (!isFile(target)) fail(`missing markdown twin: ${pathname}`);
      // Every Markdown twin must have an HTML page at the same route.
      const html = path.join(dist, pathname.slice(0, -3), "index.html");
      if (!isFile(html)) fail(`markdown twin has no page: ${pathname}`);

      // Twins are fetched on their own, out of context, so a relative link is
      // a dead end. They must all be rewritten to site or GitHub URLs.
      if (isFile(target)) {
        const twin = readFileSync(target, "utf8");
        const relative = twin.matchAll(
          /\]\((?![a-z][a-z0-9+.-]*:|\/|#)([^)\s]+)\)/gi,
        );
        for (const [, href] of relative) {
          fail(`relative link in ${pathname}: ${href}`);
        }
      }
    } else if (!isFile(target) && !isFile(path.join(target, "index.html"))) {
      fail(`link does not resolve on the site: ${pathname}`);
    }
    continue;
  }

  if (url.startsWith(REPO_URL)) {
    const rest = url.slice(REPO_URL.length);
    const repoPath = rest.match(/^\/(?:blob|tree)\/[^/]+\/(.+)$/);
    if (!repoPath) {
      fail(`unexpected repository URL: ${url}`);
      continue;
    }
    const local = path.join(repoRoot, repoPath[1]);
    if (!existsSync(local))
      fail(`repository path does not exist: ${repoPath[1]}`);
    continue;
  }

  fail(`link "${title}" points outside this site and repository: ${url}`);
}

if (checked.length === 0) {
  fail("the file contains no links");
}

// --- Report ---------------------------------------------------------------

if (problems.length > 0) {
  console.error(`✗ llms.txt failed ${problems.length} check(s):`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

const sections = content.filter((line) => line.startsWith("## ")).length;
console.log(
  `✓ llms.txt: ${sections} sections, ${checked.length} links, ${lines.length} lines.`,
);
