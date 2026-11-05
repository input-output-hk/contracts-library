/**
 * `/llms.txt` — an index of this site for agents.
 *
 * The format is defined at https://llmstxt.org: an H1, a blockquote summary,
 * optional prose, then H2 sections that are lists of `[name](url): note` links.
 * Agents read this file first and fetch the linked Markdown only as needed, so
 * it stays short and every link points at a Markdown twin rather than at HTML.
 *
 * Everything below is derived from `manifest.ts`, so adding a contract to the
 * catalog adds it here. `scripts/check-llms.mjs` verifies the result.
 */

import { access } from "node:fs/promises";
import path from "node:path";

import type { APIRoute } from "astro";

import {
  type Contract,
  contracts,
  docUrl,
  projectDocs,
  REPO_BRANCH,
  REPO_URL,
} from "../lib/manifest";
import { repoRoot } from "../lib/repo";

export const prerender = true;

const SITE = (import.meta.env.SITE || "https://contracts-library.io").replace(
  /\/$/,
  "",
);

/**
 * Documents in `docs/` that the site does not render yet. They are still worth
 * pointing agents at, but only as an `Optional` entry: several are drafts, and
 * the root file must not present them as settled.
 */
const optionalDocs = [
  {
    file: "PRD.md",
    title: "Product requirements",
    note: "Goals, scope, and the criteria used to select contracts.",
  },
  {
    file: "ROADMAP.md",
    title: "Roadmap",
    note: "Milestones and the order in which contracts are specified and delivered.",
  },
].map((doc) => ({
  ...doc,
  url: `${REPO_URL}/blob/${REPO_BRANCH}/docs/${doc.file}`,
}));

/** The note that follows a contract document's link. */
function contractNote(
  contract: Contract,
  docSlug: string,
  description: string,
): string {
  // Report state once, on the authoritative document, rather than on every row.
  if (docSlug !== "spec") return description;
  const draft =
    contract.specStatus === "draft" ? " The specification is a draft." : "";
  return `${description} Status: ${contract.status}.${draft}`;
}

function link(title: string, url: string, note: string): string {
  return `- [${title}](${url}): ${note}`;
}

async function assertDocsExist(): Promise<void> {
  const files = [
    ...contracts.flatMap((contract) => contract.docs.map((doc) => doc.file)),
    ...projectDocs.map((doc) => doc.file),
    ...optionalDocs.map((doc) => doc.file),
  ];
  const missing: string[] = [];
  for (const file of files) {
    try {
      await access(path.join(repoRoot, "docs", file));
    } catch {
      missing.push(`docs/${file}`);
    }
  }
  if (missing.length > 0) {
    throw new Error(
      `llms.txt points at documents that do not exist: ${missing.join(", ")}`,
    );
  }
}

export const GET: APIRoute = async () => {
  await assertDocsExist();

  const lines: string[] = [
    "# ContractsLibrary",
    "",
    "> A library of standardized, reusable smart contracts for Cardano, shipped",
    "> as on-chain (Aiken) and off-chain (TypeScript) pairs with",
    "> implementation-independent specifications and machine-checked formal proofs.",
    "",
    "Read this library in three layers, in order:",
    "",
    "- **Use**: drive a finished contract through its off-chain builders.",
    "- **Compose**: import the parameterized on-chain predicates and off-chain",
    "  helpers to build something new.",
    "- **Fork**: copy a contract's `onchain/`, `offchain/`, and `docs/<contract>/`",
    "  modules and modify them.",
    "",
    "Four rules that matter when answering questions about this library:",
    "",
    "- The specification in `docs/<contract>/spec.md` is the source of truth.",
    "  On-chain and off-chain code are correct insofar as they match the spec,",
    "  not insofar as they match each other.",
    "- This library is pre-release: it is not published to any package registry.",
    "  Consume it by cloning the repository.",
    '- A status such as "In progress" describes implementation state, not audit',
    "  state. Do not describe a contract as audited unless its status is",
    '  "Audited / Verified".',
    "- The Architecture entries below link to their Markdown twins at the same",
    "  route with `.md` appended. Contract documents link to GitHub, where they",
    "  live in `docs/<contract>/`.",
    "",
    "## Contracts",
    "",
  ];

  for (const contract of contracts) {
    for (const doc of contract.docs) {
      lines.push(
        link(
          `${contract.name} — ${doc.title}`,
          docUrl(doc.file),
          contractNote(contract, doc.slug, doc.summary ?? contract.summary),
        ),
      );
    }
  }

  lines.push("", "## Architecture", "");
  for (const doc of projectDocs) {
    lines.push(
      link(
        doc.title,
        `${SITE}/project/${doc.slug}.md`,
        doc.summary ?? "Canonical project documentation.",
      ),
    );
  }

  lines.push(
    "",
    "## Implementation",
    "",
    link(
      "On-chain validators",
      `${REPO_URL}/tree/${REPO_BRANCH}/onchain`,
      "Aiken source and tests for every validator.",
    ),
    link(
      "Off-chain builders",
      `${REPO_URL}/tree/${REPO_BRANCH}/offchain/meshjs/lib`,
      "MeshJS transaction builders and their tests.",
    ),
    link(
      "Compiled blueprint",
      `${REPO_URL}/blob/${REPO_BRANCH}/onchain/plutus.json`,
      "CIP-57 blueprint for every validator.",
    ),
    "",
    "## Optional",
    "",
  );
  for (const doc of optionalDocs) {
    lines.push(link(doc.title, doc.url, doc.note));
  }

  return new Response(`${lines.join("\n").trimEnd()}\n`, {
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
};
