/**
 * Absolute paths of the two roots the build needs.
 *
 * Astro bundles endpoint code before running it, so `import.meta.url` inside a
 * page points at a chunk in `dist/.prerender/`, not at the source file. Walk up
 * from the working directory instead: `astro build` and `astro dev` both run
 * with the website directory as the cwd, but starting from whichever directory
 * does work keeps this resilient to `--root` style invocations.
 */

import { existsSync } from "node:fs";
import path from "node:path";

function findRepoRoot(start: string): string {
  let dir = start;
  for (let depth = 0; depth < 5; depth += 1) {
    if (
      existsSync(path.join(dir, "docs")) &&
      existsSync(path.join(dir, "website"))
    ) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error(
    `Could not find the repository root above ${start}: expected a directory containing both docs/ and website/.`,
  );
}

/** `<repo>` */
export const repoRoot = findRepoRoot(process.cwd());

/** `<repo>/website` */
export const websiteRoot = path.join(repoRoot, "website");
