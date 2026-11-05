/**
 * Rewrites relative links in canonical Markdown so the prose in `docs/` reads
 * correctly both in the repository and on the website.
 *
 * Inside the repo, `docs/settings/usage.md` links to `../../onchain/...` and
 * `spec.md`. Neither resolves once the file is published, so this plugin
 * resolves every relative link against the file's real location and then:
 *
 *  - links to a project document the site renders go to that site route;
 *  - links to contract documents and other `docs/` prose go to GitHub;
 *  - links to code, tests, blueprints and PDFs go to GitHub (or a public asset).
 *
 * Links that resolve outside the repository are left alone.
 *
 * `resolveRepoLink()` is exported because the Markdown twins served at
 * `<route>.md` need the same mapping, only with a `.md` suffix on the routes.
 * Keeping one implementation is what stops HTML and Markdown from disagreeing
 * about where a link goes.
 */

import path from "node:path";

export interface RepoLinkOptions {
  /** Absolute path to the repository root. */
  repoRoot: string;
  /** Repository-relative file path -> site route. See `docRouteMap()`. */
  routes: Map<string, string>;
  repoUrl: string;
  branch: string;
  /**
   * Appended to routes, so the Markdown twins can link to other Markdown twins
   * (`/project/architecture.md`) while the HTML render links to pages
   * (`/project/architecture`).
   */
  routeSuffix?: string;
}

type AnyNode = {
  type?: string;
  url?: string;
  children?: AnyNode[];
  value?: string;
};

const isRelative = (url: string) => !/^(?:[a-z][a-z0-9+.-]*:|\/|#)/i.test(url);

const splitHash = (url: string) => {
  const hashIndex = url.indexOf("#");
  return hashIndex === -1
    ? { pathname: url, hash: "" }
    : { pathname: url.slice(0, hashIndex), hash: url.slice(hashIndex) };
};

/**
 * Resolve one relative link found in `sourceFile`.
 *
 * Returns `undefined` when the link is not relative or resolves outside the
 * repository, in which case the caller must leave it untouched.
 */
export function resolveRepoLink(
  url: string,
  sourceFile: string,
  options: RepoLinkOptions,
): string | undefined {
  const { pathname, hash } = splitHash(url);
  if (!pathname || !isRelative(pathname)) return undefined;

  const target = path.resolve(path.dirname(sourceFile), pathname);
  const relative = path
    .relative(options.repoRoot, target)
    .split(path.sep)
    .join("/");

  if (relative.startsWith("..") || path.isAbsolute(relative)) return undefined;

  const mapped = options.routes.get(relative);
  if (mapped) return `${mapped}${options.routeSuffix ?? ""}${hash}`;

  // Anything else that lives in the repo is served by GitHub: code, tests,
  // blueprints, PDFs, and docs the site does not render yet.
  return `${options.repoUrl}/blob/${options.branch}/${relative}${hash}`;
}

export function remarkRewriteLinks(options: RepoLinkOptions) {
  const { repoRoot, routes, repoUrl, branch } = options;

  return () => (tree: AnyNode, file: { path?: string; history?: string[] }) => {
    const filePath = file.path ?? file.history?.[0];
    if (!filePath) return;

    const rewrite = (node: AnyNode) => {
      if (node.type !== "link" || !node.url) return;
      const resolved = resolveRepoLink(node.url, filePath, {
        repoRoot,
        routes,
        repoUrl,
        branch,
      });
      if (resolved) node.url = resolved;
    };

    const walk = (node: AnyNode) => {
      rewrite(node);
      if (node.children) for (const child of node.children) walk(child);
    };

    // Drop the document's own H1: Starlight supplies the page title, and the
    // canonical files all start with one.
    if (tree.children) {
      const firstIndex = tree.children.findIndex(
        (child) => child.type !== "yaml",
      );
      const first = tree.children[firstIndex];
      if (
        first?.type === "heading" &&
        (first as { depth?: number }).depth === 1
      ) {
        tree.children.splice(firstIndex, 1);
      }
    }

    walk(tree);
  };
}
