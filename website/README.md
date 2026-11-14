# Website

The documentation site for ContractsLibrary, served at
[contracts-library.io](https://contracts-library.io). It is built with
[Astro](https://astro.build) and [Starlight](https://starlight.astro.build).

The site owns presentation only. The contract catalog comes from a manifest and
the canonical specifications and usage guides stay in [`../docs/`](../docs);
the site summarizes each specification, renders its usage guide in full, and
links every canonical document on GitHub.

## Prerequisites

- Node.js >= 22.12 (see `engines` in `package.json`).
- No external checkout is needed: `tx-diagram-ui` is vendored under
  [`tx-diagram-ui/`](tx-diagram-ui/), so `npm install` is self-contained.

## Running

```sh
cd website
npm install
npm run dev            # http://localhost:4321
```

`npm run dev` serves with hot reload. To check a production build:

```sh
npm run build
npm run preview
```

| Command              | What it does                                            |
| -------------------- | ------------------------------------------------------- |
| `npm run dev`        | Development server with hot reload.                     |
| `npm run build`      | Static build into `dist/`.                              |
| `npm run preview`    | Serves the last build.                                  |
| `npm run check`      | Type-checks Astro, Svelte and content collections.      |
| `npm run check:llms` | Validates `dist/llms.txt` against the pages that exist. |

## Verify before opening a PR

```sh
npm run check && npm run build && npm run check:llms
```

Run `build` before `check:llms`: the checker inspects the generated `dist/`.
Formatting is handled at the repository root with `npm run format`, which needs
its own `npm install` at the root.

## Content model

- `src/content/docs/` — pages authored for the site: the landing page, the
  newcomer primer, install instructions, and each contract's overview,
  transactions and specification & usage pages.
- `../docs/` — canonical specs and usage guides. Project documents are rendered
  by `src/pages/project/[doc].astro` from the `upstream` content collection;
  contract specs are linked on GitHub, while each contract's usage guide is
  rendered into its site guide page. The site never copies their prose.
- `src/lib/manifest.ts` — the catalog: one entry per contract (slug, name,
  summary, status, category, spec status) mapping it to its documents in
  `docs/`. Adding a contract starts here.
- `src/data/<contract>/*.json` — data for the transaction and lifecycle
  diagrams, validated at build time.
- `tx-diagram-ui/` — the vendored transaction-diagram package. It is a local
  package imported by name; see its [`README`](tx-diagram-ui/README.md).
- `src/pages/` — project document routes and their Markdown twins
  (`<route>.md`), plus `llms.txt`.
- `src/components/` — `ContractGrid`, `StatusBadge`, `TxChain`, `TxDiagram`,
  `CanonicalUsage` and the Starlight overrides in `overrides/`.
- `src/lib/remark-rewrite-links.ts` — rewrites relative links in `docs/` so the
  same prose works on GitHub, in the rendered project pages, and in the
  Markdown twins.
- `astro.config.mjs` — Starlight config, the hand-written sidebar, the Aiken
  grammar for code samples, and the Markdown pipeline.
- `scripts/check-llms.mjs` — validates `/llms.txt`; it fails on a broken link,
  a missing Markdown twin, or a relative link inside a twin.

`dist/` and `.astro/` are build output and gitignored.

## Page roles

Each contract has three site pages: overview (decide and orient), transactions
(show the shape), and specification & usage (summarize the specification, then
render the full canonical usage guide). Each page has one job:

| Page                  | Job                                                                     | Must not contain                         |
| --------------------- | ----------------------------------------------------------------------- | ---------------------------------------- |
| Overview              | Decide and orient                                                       | roles tables, mechanics, invariant lists |
| Transactions          | Show the transaction shape                                              | roles tables, exact constraint tables    |
| Specification & usage | Summarize the specification, then render the full canonical usage guide | an abridged or rewritten usage guide     |

The specification remains canonical in `docs/`; when a summary disagrees with
it, the specification wins.

## Adding a contract

1. Write `docs/<slug>/spec.md` and `docs/<slug>/usage.md`.
2. Implement the on-chain and off-chain layers.
3. Add one entry to `contracts[]` in `src/lib/manifest.ts`.
4. Add the overview, transactions and guide pages under
   `src/content/docs/contracts/<slug>/`.
5. Add the contract to the sidebar in `astro.config.mjs`.
6. Run `npm run check && npm run build && npm run check:llms`.
