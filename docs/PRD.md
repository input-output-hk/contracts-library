# ContractsLibrary: Product Requirements Document

> Status: Draft · Owner: Robertino Martinez
> Companion documents: [`ARCHITECTURE.md`](./ARCHITECTURE.md) (composability architecture), Roadmap (milestones & dates).

## 1. Summary

ContractsLibrary is an **OpenZeppelin-like library of standardized, reusable smart contracts for Cardano**, shipped as **on-chain + off-chain pairs**, with an initial focus on building blocks and DeFi primitives.

Inspired by OpenZeppelin's role in the EVM ecosystem, the library provides battle-tested, ready-to-use contract implementations that developers can adopt as turnkey protocols, import as part of their protocol, fork as a starting point, or compose from lower-level utilities. It is a **100% open-source public good**.

By providing canonical implementations of common smart-contract use cases, the library significantly **reduces the time and risk required to build on Cardano**, especially for developers new to the ecosystem.

## 2. Background & Motivation

The EVM ecosystem matured rapidly in part because OpenZeppelin gave developers vetted, reusable contract implementations. Cardano lacks an equivalent: developers repeatedly re-implement the same primitives (vesting, escrow, token standards, AMMs), each time re-incurring design and security risk.

Existing Cardano libraries operate at a *lower* level of abstraction:

- [Vodka](https://github.com/sidan-lab/vodka): small on-chain utility functions.
- [Anastasia Labs' design-patterns](https://github.com/Anastasia-Labs/design-patterns): generic on-chain patterns.

**ContractsLibrary operates at the use-case level**: full contracts, both on-chain and off-chain. We **stand on the shoulders of** libraries like those rather than replacing them.

Sources of demand and prior art we draw on:

- [cardano-template-and-ecosystem-monitoring](https://github.com/cardano-foundation/cardano-template-and-ecosystem-monitoring): real-world use cases that signal which patterns are most needed.
- [Mesh SDK contract package](https://github.com/MeshJS/mesh/tree/main/packages/mesh-contract) and the [Cardano Developer Portal example contracts](https://developers.cardano.org/docs/build/smart-contracts/example-contracts/): existing implementations that inform our designs.
- Existing protocols deployed on Cardano.

## 3. Goals & Non-Goals

### 3.1 Goals

- Ship **at least 5 ready-to-audit contracts** as on-chain + off-chain pairs.
- Make the **turnkey path delightful for newcomers**, so developers new to Cardano can configure and deploy a contract with minimal friction.
- Establish the **infrastructure** (monorepo, build, distribution, testing, specs) and a **website** that make the library discoverable and usable.
- Provide every contract with a **decoupled formal specification** to enable later formal verification and re-implementation in other languages/frameworks.
- Build a **community resource**: multi-language support and a clear contribution path so the ecosystem can extend it.
- First-class **AI-agent developer experience** (prompts, skills, agent affordances).

### 3.2 Non-Goals

1. **We do not operate or host protocols, and never custody user funds.** The library is code, not a service.
2. **We do not commit to deploying canonical reference scripts on mainnet.** We *design for* that possibility; whether we deploy is undecided.
3. **No interactive contract "Wizard"/configurator in v1.** Listed as a roadmap aspiration only (§10).
4. **Graduation to "stable" requires an audit *or* formal-methods verification.** Either path qualifies.
5. **This project's committed scope ends at Ready-to-audit.** We make contracts *audit-ready* and publish results if/when verification happens; we make **no promise that contracts pass an audit** within this scope.
6. **Not a general-purpose utility library.** We build on vodka / design-patterns; we do not duplicate them.

## 4. Target Users

In priority order. **DX optimizes for the primary group, and within it for Cardano newcomers; ease of use is paramount.**

1. **dApp developers** (primary): building products, want a vetted implementation to drop in or fork. **Newcomers to Cardano are a deliberate focus.**
2. **Protocol / contract authors** (secondary): want building blocks and patterns to compose into novel contracts.
3. **Auditors & educators** (tertiary): use canonical implementations as reference material.

## 5. Principles

1. **Newcomer DX is paramount.** Among unavoidable trade-offs, we err toward ease of use and developer experience over execution cost, speed, and even composability, **with security as the sole non-negotiable exception. Security is never compromised.**
2. **Composability by construction.** All contracts follow the composability conventions in [`ARCHITECTURE.md`](./ARCHITECTURE.md): validators are well-behaved predicates that avoid global assumptions about transaction shape so contracts compose freely in shared transactions.
3. **Pluggable authorization (exploratory).** No contract hardcodes an authorization mechanism; all authorization flows through a shared interface (single-key, script-based multisig/DAO/smart-wallet, native script). See `ARCHITECTURE.md` §2.
4. **On-chain + off-chain pairs.** Every contract ships both layers (§6).
5. **Multi-language and community-extensible.** Off-chain support is language-agnostic at the spec level; contributors can add their own language implementations.
6. **Specs are first-class.** Each contract has a decoupled specification to enable formal verification.
7. **AI-agent DX is first-class.** We ship prompts, agent skills, and other affordances for developers building with LLM agents.
8. **Reduce doc fragmentation.** We contribute to the Cardano Developer Portal first; our own site hosts only what cannot live there, plus references.

## 6. Product Overview: What We Ship

### 6.1 Consumption model

A layered model, with the **turnkey path as the headline newcomer experience**:

1. **Use (turnkey-via-configuration)**: the default. A developer takes a finished or near-finished contract, supplies **parameters** to mint **their own instance**, and ships. Some contracts are usable as-is; some need only parameters; some need small additions. We evaluate **case-by-case** and provide a **precompiled blueprint whenever feasible**.
2. **Fork / customize**: copy the on-chain module(s) + off-chain builder and modify for specific needs.
3. **Compose**: import lower-level on-chain validation functions / off-chain helpers to build something new.

> Newcomers may still need to write **some** Aiken; it cannot be avoided in every case. We minimize it case-by-case and provide the precompiled contract wherever we can.

### 6.2 On-chain layer (Aiken)

- The library exposes each validator's logic as **parameterized functions**. A consumer's `validator` block is a **thin wrapper** that passes parameters and calls our logic.
- Distributed as an **Aiken package**.
- Optionally ships a **ready-to-deploy reference validator** wiring the logic together.
- Conforms to the composability principles in `ARCHITECTURE.md`.

### 6.3 Off-chain layer

- The **primary developer-facing API.** Constructs valid transactions for every action a contract supports.
- **Language-agnostic at the spec level**: each contract defines an off-chain *specification* (actions; required inputs/outputs/redeemers/datums per transaction) that any language package implements against.
- **v1 implementations: MeshJS and Tx3.** Additional languages (e.g., Go) are contributor-extensible and roadmapped, not gating.
- Supports **off-chain parameter application** (apply parameters to a precompiled blueprint at runtime) so a pure off-chain developer can parameterize and deploy without an Aiken toolchain where the contract allows it.

### 6.4 Specifications

- A **separate folder, decoupled from implementation**, holding each contract's spec (state machine / datum-redeemer transitions, invariants, threat model & known assumptions).
- Purpose: enable **formal-methods teams to verify implementations** later, and serve as the authoritative behavioral contract.

### 6.5 AI-agent affordances

- Ship **prompts, agent skills, and related tooling** so developers using LLM agents get first-class support integrating and configuring contracts.

## 7. Contract Catalog

This is the **only section that enumerates specific contracts.** The rest of the PRD is generic to any contract set. Contracts enter and exit this catalog freely; the rest of the document does not change when they do.

### 7.1 Selection criteria

A candidate earns evaluation when it has (or seems to have):

1. **Real ecosystem demand** (signaled by use-case monitoring and existing implementations).
2. **Reusability & composability**: a clear building-block or primitive role.
3. **A clear canonical design**: a well-understood "right way" to implement it.
4. **Audit-tractable scope**: can plausibly reach Ready-to-audit.

### 7.2 Process: explore, then triage

We do **not** treat the catalog as a fixed commitment. Instead, we:

1. **Explore** many candidates with lightweight exploratory work.
2. **Triage** each into **implement now / later / never**, recording the decision (and reason for "never") in the table.

An **exploration** produces: a lightweight design sketch, a complexity/risk read, a composability check against `ARCHITECTURE.md`, and a recommendation. Declined candidates **stay in the table** with a one-line reason so the decision is documented.

### 7.3 Status taxonomy


| Status | Meaning |
|---|---|
| **Candidate** | Listed, not yet examined. |
| **Exploring** | Under exploratory design/spike. |
| **Selected: Now** | Chosen for current implementation. |
| **Selected: Later** | Worth doing, deferred. |
| **Declined** | Explored and decided against (reason recorded). |
| **In progress** | Actively being implemented. |
| **Ready-to-audit** | Meets the Definition of Ready-to-Audit (§8). |
| **Audited / Verified** | Audit complete or formally verified; eligible for the stable channel (§9). |


### 7.4 Catalog

> Status reflects current understanding and changes as exploration/triage proceeds. Detailed scheduling lives in the Roadmap document. **Details** links to the in-depth explanation for each candidate (a GitHub issue, PR, or separate document) covering its exploration, design, and triage decision.


| Contract | Category | Description | Status | Details |
|---|---|---|---|---|
| Vesting | Building block | Time-locked token release (linear / cliff). | Candidate | TBD |
| CIP-68 metadata | Token standard | Rich, updatable on-chain token metadata. | Candidate | TBD |
| Programmable Tokens (CIP-113) substandards | Token standard | Permissioned / transfer-restricted tokens. | Candidate | TBD |
| Escrow / Atomic Swap | DeFi primitive | Trustless exchange of assets between parties. | Candidate | TBD |
| AMM DEX / Liquidity Pool | DeFi primitive | Automated market maker with liquidity pools. | Candidate | TBD |
| Lending | DeFi primitive | Collateralized lending/borrowing. | Candidate | TBD |
| Auction | DeFi primitive | On-chain auctions (English/Dutch). | Candidate | TBD |
| Multisig / Smart wallet | Building block | Script-based authorization schemes. | Candidate | TBD |
| Oracle | Building block | On-chain data feed consumption pattern. | Candidate | TBD |
| Order-book DEX | DeFi primitive | Order-book-based exchange. | Candidate | TBD |


*The committed set of "at least 5 ready-to-audit" contracts emerges from the explore/triage process; it is not fixed in advance.*

## 8. Quality Bar: Definition of "Ready-to-Audit"

A contract is **Ready-to-audit** when it has **all** of:

1. **On-chain**: Aiken module(s) exposing parameterized logic functions + a reference validator; conforms to `ARCHITECTURE.md` composability principles; no known unhandled edge cases.
2. **Tests**: comprehensive on-chain unit + property tests (happy path + adversarial/negative cases) with a stated coverage expectation; off-chain integration tests against an emulator.
3. **Specification**: written spec in the specs folder (state machine / datum-redeemer transitions, invariants, threat model & known assumptions).
4. **Off-chain**: **two** reference implementations (starting with MeshJS + Tx3), each covering every action, with end-to-end tests.
5. **Docs**: usage guide + API reference + at least one worked example.
6. **Reproducible build**: pinned toolchain versions; deterministic blueprint output.

## 9. Versioning, Distribution & Stability

- **Single library-wide semantic version** across all contracts (matches OpenZeppelin; per-contract versioning rejected as too complex).
- **Distribution**: on-chain via Aiken's package ecosystem; off-chain via each language's native registry (npm for MeshJS, etc.). The **monorepo is the single source of truth**.
- **Cross-layer pinning**: each off-chain package version declares the on-chain blueprint version/hash it targets, so off-chain code and on-chain logic cannot silently drift.
- **Two channels** (modeled on OpenZeppelin's stable-vs-drafts/RC separation):
  - **stable**: only contracts that are **Audited or formally verified**.
  - **dev / preview**: everything else (Ready-to-audit and below).
  - Implemented via native mechanisms (npm dist-tags `latest`/`next`; tagged releases / `dev` namespace for Aiken).
- **Scope note**: within this project's committed scope, contracts reach **Ready-to-audit** and therefore land in the **dev** channel. Promotion to **stable** (via audit or formal verification) is designed-in but **future / out of current scope**.

## 10. Documentation & Website

**Strategy: Developer Portal first, to reduce ecosystem doc fragmentation.** Most content goes to the [Cardano Developer Portal](https://developers.cardano.org/), with references from our own site. Only what cannot live there is hosted on our website.

v1 website scope:

- **Catalog browser**: the contract table, filterable by category / status / channel.
- **Per-contract pages**: overview, spec, usage guide per off-chain language, API reference, security notes / known assumptions, audit/verification status + report links.
- **Getting-started guides**: newcomer-oriented, end-to-end (e.g., "deploy your first vesting contract").
- **Generated, not hand-maintained** where possible: API references and the catalog pull from the monorepo (blueprints, package metadata, Status) so docs cannot drift from code.

**Roadmap aspiration (no commitment):** an interactive **Wizard / configurator** that generates a configured contract (à la OpenZeppelin Wizard) or an LLM-based equivalent.

## 11. Repository Structure

Monorepo, source of truth for all layers:

```
/on-chain          Aiken workspace (lib/<contract>/, validators/)
/off-chain
  /meshjs          MeshJS implementations
  /tx3             Tx3 implementations
  /<lang>          contributor-added languages
/specs             decoupled per-contract specifications (for formal methods)
/docs              PRD, ARCHITECTURE, contributor docs
/website           catalog browser + generated docs site
/ai                prompts, agent skills, LLM-agent affordances
```

*(Indicative; exact layout finalized during infrastructure setup.)*

## 12. Success Metrics

Directional (hard targets/dates live in the Roadmap):

1. **≥5 contracts reach Ready-to-audit** (the brief's bar).
2. **Adoption**: package downloads, GitHub forks/stars, contracts used in real dApps.
3. **Dev Portal contributions merged.**
4. **Verification progress** (directional, not committed): contracts that go on to be audited or formally verified.

## 13. License

**Apache-2.0** for all artifacts: on-chain, off-chain, specs, docs.

## 14. Open Questions & Future Work

- Whether **IOG deploys canonical reference scripts** for non-parameterized contracts (designed-for, undecided).
- **Additional off-chain languages** beyond MeshJS + Tx3.
- The interactive **Wizard / configurator**.
- **Formal verification** of implementations via the specs folder.
- **Audits** of contracts (beyond current scope).

## 15. Relationship to Other Documents & Libraries

- **`ARCHITECTURE.md`**: defines the composability architecture and authorization system that all contracts in this catalog must follow. This PRD defers all composability/authorization specifics to it.
- **Roadmap (separate doc)**: milestones, dates, and treasury deliverables.
- **vodka / design-patterns**: lower-level libraries we build on, not replace.
