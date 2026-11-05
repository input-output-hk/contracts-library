// @ts-check
import path from "node:path";
import { fileURLToPath } from "node:url";

import { unified } from "@astrojs/markdown-remark";
import starlight from "@astrojs/starlight";
import svelte from "@astrojs/svelte";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

import aikenGrammar from "./src/assets/grammars/aiken.tmLanguage.json";
import { docRouteMap, REPO_BRANCH, REPO_URL } from "./src/lib/manifest.ts";
import { remarkRewriteLinks } from "./src/lib/remark-rewrite-links.ts";

const repoRoot = path.resolve(
  fileURLToPath(new URL(".", import.meta.url)),
  "..",
);

// https://astro.build/config
export default defineConfig({
  site: "https://contracts-library.io",
  trailingSlash: "never",
  integrations: [
    starlight({
      title: "ContractsLibrary",
      description:
        "Standardized, reusable smart contracts for Cardano — on-chain, off-chain, and formally specified.",
      customCss: [
        "@fontsource-variable/inter",
        "@fontsource-variable/roboto-mono",
        "./src/styles/global.css",
      ],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: REPO_URL,
        },
      ],
      components: {
        Header: "./src/components/overrides/Header.astro",
        Footer: "./src/components/overrides/Footer.astro",
      },
      sidebar: [
        {
          label: "Get started",
          items: [
            { label: "Cardano in 15 minutes", link: "/get-started/cardano" },
            { label: "Install & setup", link: "/get-started/install" },
          ],
        },
        {
          label: "Contracts",
          items: [
            { label: "Catalog", link: "/contracts" },
            {
              label: "Settings",
              items: [
                { label: "Overview", link: "/contracts/settings" },
                {
                  label: "Transactions",
                  link: "/contracts/settings/transactions",
                },
                {
                  label: "Specification & usage",
                  link: "/contracts/settings/guide",
                },
              ],
            },
          ],
        },
        {
          label: "Project",
          items: [
            { label: "Architecture", link: "/project/architecture" },
            { label: "GitHub", link: REPO_URL, attrs: { target: "_blank" } },
          ],
        },
      ],
      expressiveCode: {
        themes: ["starlight-dark"],
        useStarlightDarkModeSwitch: false,
        shiki: {
          // Vendored so Aiken samples in the specs are highlighted. Shiki looks
          // languages up by `name`, and the upstream grammar capitalises it.
          langs: [{ ...aikenGrammar, name: "aiken" }],
          // `docs/dao/spec.md` fences its formal notation as ```math; render it
          // as plain text rather than warn on an unknown language.
          langAlias: { math: "text" },
        },
      },
    }),
    // Only used by the transaction diagrams; the rest of the site is Astro/MDX.
    svelte(),
  ],
  markdown: {
    processor: unified({
      remarkPlugins: [
        remarkRewriteLinks({
          repoRoot,
          routes: docRouteMap(),
          repoUrl: REPO_URL,
          branch: REPO_BRANCH,
        }),
      ],
    }),
  },
  vite: {
    plugins: [tailwindcss()],
    // The vendored tx-diagram-ui ships raw .svelte/.ts source (no dist build),
    // so it must be compiled by our pipeline instead of pre-bundled by esbuild.
    optimizeDeps: { exclude: ["tx-diagram-ui"] },
    ssr: { noExternal: ["tx-diagram-ui"] },
  },
});
