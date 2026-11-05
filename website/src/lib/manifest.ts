/**
 * The contract catalog, as the website sees it.
 *
 * This is the single place that maps a contract to its canonical documents in
 * the repository's top-level `docs/` folder. The site summarizes the spec and
 * usage in `src/content/docs/contracts/<slug>/guide.mdx` and links the full
 * documents on GitHub; it does not render them itself.
 *
 * Keeping the mapping here means a new contract needs an entry here plus a
 * directory in `docs/` — no prose duplication, no drift.
 */

export const REPO_URL = "https://github.com/input-output-hk/contracts-library";
export const REPO_BRANCH = "main";

/** GitHub URL for a canonical document in `docs/`. */
export function docUrl(file: string): string {
  return `${REPO_URL}/blob/${REPO_BRANCH}/docs/${file}`;
}

export type ContractStatus =
  | "Candidate"
  | "Exploring"
  | "Selected: Now"
  | "Selected: Later"
  | "In progress"
  | "Ready-to-audit"
  | "Audited / Verified";

export type ContractCategory =
  | "DeFi"
  | "Governance"
  | "Infrastructure"
  | "Tokenization";

/** One canonical Markdown document from `docs/`, surfaced on the site. */
export interface DocRef {
  /** Path relative to `docs/`, with its extension. e.g. `settings/spec.md`. */
  file: string;
  /** Page slug: `/contracts/<contract>/<slug>` or `/project/<slug>`. */
  slug: string;
  /** Sidebar and page title. Kept short; the document's own H1 is dropped. */
  title: string;
  /**
   * One line describing this document, used by `llms.txt`. Falls back to the
   * contract's summary when omitted.
   */
  summary?: string;
}

export interface Contract {
  /** Folder name under `docs/`; also the route segment. */
  slug: string;
  name: string;
  /** One sentence, for the catalog card. */
  summary: string;
  status: ContractStatus;
  category: ContractCategory;
  /**
   * Whether the specification is settled. A draft spec is still the source of
   * truth for the code, but `llms.txt` flags it so agents do not quote it as
   * final.
   */
  specStatus: "draft" | "stable";
  docs: DocRef[];
}

export const contracts: Contract[] = [
  {
    slug: "settings",
    name: "Settings",
    summary:
      "Governed configuration for another protocol: changes are proposed, wait out a delay, then are applied.",
    status: "In progress",
    category: "Governance",
    specStatus: "stable",
    docs: [
      {
        file: "settings/spec.md",
        slug: "spec",
        title: "Specification",
        summary:
          "Defines the Settings UTxO, its datum, and the launch, propose, apply, and close transactions.",
      },
      {
        file: "settings/usage.md",
        slug: "usage",
        title: "Usage guide",
        summary:
          "How to deploy, operate, and consume a Settings instance, including the off-chain builders.",
      },
    ],
  },
  {
    slug: "vesting",
    name: "Linear Vesting",
    summary:
      "Release a bundle of ada or native tokens to a beneficiary on a linear schedule, with locker recovery after a grace period.",
    status: "In progress",
    category: "Tokenization",
    specStatus: "draft",
    docs: [
      {
        file: "vesting/spec.md",
        slug: "spec",
        title: "Specification",
        summary:
          "Defines the vesting datum, the Claim and Cancel actions, the linear schedule, and the count-preserving continuation rule.",
      },
      {
        file: "vesting/usage.md",
        slug: "usage",
        title: "Usage guide",
        summary:
          "How to deploy the vesting script and build Lock, Claim, and Cancel transactions with the MeshJS builders.",
      },
    ],
  },
  {
    slug: "dao",
    name: "DAO",
    summary:
      "Token-weighted governance for a protocol and its treasury: stake, propose, vote, and execute the winning effect.",
    status: "In progress",
    category: "Governance",
    specStatus: "draft",
    docs: [
      {
        file: "dao/spec.md",
        slug: "spec",
        title: "Specification",
        summary:
          "Defines the stake, proposal, and vote validators, the proposal lifecycle, and the effect-script execution model.",
      },
      {
        file: "dao/usage.md",
        slug: "usage",
        title: "Usage guide",
        summary:
          "How to deploy the DAO validators, run stake positions, and drive proposals, voting, and tallying with the off-chain builders.",
      },
    ],
  },
  {
    slug: "smart-wallet",
    name: "Smart Wallet",
    summary:
      "A programmable wallet with a base M-of-N signature floor and pluggable spending and deposit restrictions.",
    status: "In progress",
    category: "Infrastructure",
    specStatus: "draft",
    docs: [
      {
        file: "smart-wallet/spec.md",
        slug: "spec",
        title: "Specification",
        summary:
          "Defines the wallet NFT, datum maps, M-of-N floor, and the mint, spend, deposit, update, and close actions.",
      },
      {
        file: "smart-wallet/usage.md",
        slug: "usage",
        title: "Usage guide",
        summary:
          "How to deploy a wallet, run its lifecycle, and use the reference delegated withdrawal scripts.",
      },
    ],
  },
];

export function getContract(slug: string): Contract | undefined {
  return contracts.find((contract) => contract.slug === slug);
}

/** Project-level documents from `docs/` that the site publishes. */
export const projectDocs: DocRef[] = [
  {
    file: "ARCHITECTURE.md",
    slug: "architecture",
    title: "Architecture",
    summary:
      "How validators stay composable when several participate in one transaction, and the conventions that keep their assumptions from conflicting.",
  },
];

/**
 * The content-collection id Astro's `glob()` loader assigns to a file.
 *
 * The loader derives it from the file path, slugified per segment. Every
 * document we publish has an already-slug-safe path, so lowercasing the path
 * without its extension is exact.
 */
export function entryId(file: string): string {
  return file.replace(/\.md$/, "").toLowerCase();
}

/**
 * Map from a repository-relative Markdown file (e.g. `docs/ARCHITECTURE.md`)
 * to the site route that renders it. Contract documents are not rendered on the
 * site; links to them fall through to GitHub.
 */
export function docRouteMap(): Map<string, string> {
  const routes = new Map<string, string>();
  for (const doc of projectDocs) {
    routes.set(`docs/${doc.file}`, `/project/${doc.slug}`);
  }
  return routes;
}
