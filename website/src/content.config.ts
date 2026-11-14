import { docsLoader } from "@astrojs/starlight/loaders";
import { docsSchema } from "@astrojs/starlight/schema";
import { glob } from "astro/loaders";
import { defineCollection } from "astro:content";

export const collections = {
  /** Site-authored pages: landing, guides, reference. */
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),

  /**
   * The canonical documents from the repository's top-level `docs/` folder.
   * Project documents are rendered by `src/pages/project/[doc].astro`; contract
   * documents stay on GitHub and are linked from their guide pages.
   */
  upstream: defineCollection({
    loader: glob({ base: "../docs", pattern: "**/*.md" }),
  }),
};
