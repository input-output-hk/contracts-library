import type { APIRoute, GetStaticPaths } from "astro";

import { type DocRef, projectDocs } from "../../lib/manifest";
import { renderMarkdownTwin } from "../../lib/markdown-twin";

export const prerender = true;

/** `/project/<doc>.md` — see `src/lib/markdown-twin.ts`. */
export const getStaticPaths: GetStaticPaths = () =>
  projectDocs.map((doc) => ({
    params: { doc: doc.slug },
    props: { doc },
  }));

export const GET: APIRoute = async ({ props }) => {
  const { doc } = props as { doc: DocRef };
  return new Response(await renderMarkdownTwin(doc), {
    headers: { "content-type": "text/markdown; charset=utf-8" },
  });
};
