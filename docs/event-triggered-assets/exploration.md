# Exploration: CIP-113 Substandard - Event-Triggered Assets

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage is deferred to team discussion.
>
> **Tracking:** issue #28, under the CIP-113 substandards umbrella (#2) and the CIP-113 interaction investigation (#1).
>
> **Scope:** a *design/scoping* pass over one CIP-113 substandard. The eUTxO *feasibility* of the underlying mechanics (do reactive predicates permit event-conditioning; is anything autonomous) is treated as settled background and summarized in §5; this document focuses on what the substandard is, what it serves, and how its pieces decompose.

## 1. Use case

A token whose programmability governs its **state and lifecycle**, not its **ownership**. It moves as freely as a native token, its state can change in response to discrete on-chain events, and it can eventually "settle" into a plain native token once its special behavior is no longer needed.

This is deliberately **not** the transfer-permissioned profile of CIP-113 (KYC/AML gating, blacklists, regulated stablecoins), which keeps a transfer gate and is a separate substandard. The unifying idea here is **instruments that are special for a while, then become plain money.**

**Category:** Token standard (CIP-113 substandard).

## 2. Core framing: three separable primitives

The substandard is three independent mechanics. Most products need only a subset, which is the reason to standardize them separately rather than as one monolith.

- **P1 - Permissive-transfer base.** A CIP-113 programmable token that imposes **no transfer rules**: the `transfer_logic` predicate is permissive, so the token moves freely. Programmability never gates who may hold or send it.
- **P2 - Event-rule hooks.** Pluggable rules (oracle-driven or contract-driven) that **modify token state, or condition a transfer/lockup/burn, on discrete events** (a time cliff, a market resolution, a maturity, an attestation). On CIP-113 this is a `transfer_logic` or `third_party` predicate reading event state via a reference input.
- **P3 - Graduation / unwrap.** A one-way exit that **retires the programmability**, converting the programmable token into a plain native token (or burning it) once the instrument's job is done.

A key architectural consequence, established in §5: **P3 is not a cheap unwrap.** CIP-113 tokens are custodied at a shared programmable-logic base and cannot be moved to a non-programmable address, so graduation is necessarily *burn the CIP-113 token + mint a distinct native token*, which raises an asset-identity/fungibility question (§7, Q-GRAD-1). This is the load-bearing design problem of the substandard.

## 3. Mechanism

### 3.1 How it works

- **Mint** the token under a CIP-113 policy with a permissive `transfer_logic` (P1) and an attached event-rule predicate (P2). Holders trade it freely.
- **On an event**, a keeper (or the beneficiary) submits a transaction that references the event state (an oracle fact statement, a resolution UTxO, a validity interval). The P2 predicate approves the resulting state change (release, lockup, mark-claimable, burn) if and only if the event condition holds. Nothing self-executes; the predicate is reactive (§5).
- **At end of life**, an event-gated P3 transaction burns the CIP-113 token and mints the equivalent plain native token (or simply burns, for retire-style cases), removing the contract dependency.

### 3.2 Why this is worth exploring

- **It is the connective tissue of the catalog.** Linear Vesting (#3), both Prediction Markets (#7, #8), Escrow (#6), and the Streaming Payments, Royalty (CIP-102), and Merkle Airdrop candidates all express as this shape (freely-tradable token + event-driven state change + settlement exit). Standardizing P1/P2/P3 lets those compose a shared substandard instead of each re-deriving it.
- **It concentrates the novelty.** P1 and P2 are well-trodden (permissive transfers; predicate conditioning). The genuinely new, reusable, and audit-worthy piece is **P3 (graduation)**, which is also where the sharp hazards live (§5, §7).
- **It is the CIP-113-relevant slice of the "unlocked use cases" question.** A companion feasibility pass over six externally-claimed "CIP-113 unlocked" token behaviours found that the per-UTxO-conditioning cases (vesting, event-conditioning) are exactly where CIP-113 adds genuine value, while the pooled-capital cases (yield/hedging/risk-adjustment) are gated by keeper/oracle/contention constraints CIP-113 does not address. This substandard is the former; the latter are non-goals (§6).

### 3.3 Use-case catalog

Grouped by fit. "Primitives" = which of P1 (free transfer), P2 (event hooks), P3 (graduation/unwrap) the case needs.

**Strong fit: instruments with a lifecycle that ends in settlement.**

| Use case | Ecosystem analog | Primitives | Related |
|---|---|---|---|
| Token vesting (linear / cliff) | Toku RTUs, 1yr-cliff/4yr | P2 (time) + P3 | #3 |
| Employee / contributor comp (milestone) | Toku Restricted Token Units | P2 + P3 | #3 |
| Streaming vesting / payroll | Superfluid, Sablier | P2 (time) + P3 | Streaming Payments cand. |
| Airdrop that activates on TGE / unlock | Merkle drops | P1 + P2 | Merkle Airdrop cand. |
| Grants / bounties (tranche unlock) | attestation-gated release | P2 + P3 | #6 |
| Tokenized bond (coupon + maturity) | World Bank bond-i, Centrifuge | P2 + P3 (burn) | |
| Tokenized invoice / factoring | Chainlink invoice tokenization | P2 + P3 | |
| Letter of credit / trade-finance escrow | tokenized LCs | P2 + P3 | #6 |
| Options / warrants | Ribbon oTokens (strike + expiry) | P2 (exercise/expiry) + P3 | |
| Convertible notes / SAFEs | on-chain converts | P2 + P3 | |
| Prediction-market outcome tokens | Gnosis CTF, Polymarket | P1 + P2 + P3 | #7, #8 |
| Parametric insurance policy tokens | Etherisc flight/crop + Chainlink | P2 + P3 | |
| Conditional / escrow payment | oracle-attested release | P2 | #6 |
| Carbon-credit retirement | Toucan TCO2 | P2 + P3 (burn) | |
| RECs / biodiversity credits | retire-on-use | P2 + P3 (burn) | |
| Warranty / proof-of-purchase | activate on registration | P2 | |
| Subscription NFT / pass | ERC-5643 | P2 | |
| Loyalty points (boost / expiry) | promo-driven balance change | P1 + P2 | |
| Dynamic NFT / evolving game asset | dNFTs, CIP-86 metadata oracles | P2 + P3 (freeze) | #15 |
| Event ticketing | activate on date, collectible after | P2 | |
| Bonding / staking receipt | Olympus-style bonds | P2 + P3 | Vault cand. |
| Royalty / revenue-share token | Royal (3LAU), Story Protocol | P2 + P3 | Royalty CIP-102 cand. |

**Partial fit / explicit non-goals (belong to sibling standards).**

| Case | Why it does not fit here | Belongs to |
|---|---|---|
| Regulated security token with lockup | Restricted phase needs a transfer gate (violates P1); only P3 (restricted to free-float) applies | transfer-permissioned CIP-113 (#2) |
| Vote-escrow lock (veCRV) | Needs non-transferability during the lock | separate locked-governance design |
| KYC/AML-gated RWA | Transfer-permissioning first | mainstream CIP-113 |
| Yield aggregator / auto-compounder / risk-managed vault / risk-adjusted stablecoin | Pooled-capital strategy logic, not per-holder token state | Tokenized Vault candidate |

### 3.4 Dependencies

- **Oracle / event source** (building-block candidate): supplies the event fact (price, resolution, attestation) as a pull-based reference input (§5). Abstracted via a `Credential` (§4).
- **CIP-113 programmable-token policy**: the P1 base and the P2 `transfer_logic` / `third_party` predicates.
- **A native minting policy** for the P3 target token (the graduated asset), plus a keeper to submit the burn+remint.
- **A pricing/liquidity venue** where the case involves trading (outcome tokens, bonds): a DEX or Atomic Swap (#5), delegated, not reimplemented.

## 4. Authorization: rules and graduation via a `Credential`

Both the P2 event rules and the P3 graduation authority should be **pluggable `Credential`s** (the pattern in `ARCHITECTURE.md` and shared with Escrow #6 / Prediction Market #7), not hard-coded keys. A rule reads its event state as a reference input and approves the state change; the graduation authority is gated (see Q-GRAD-2) so that graduation can fire only once the same event condition the rules enforce is on-chain true, making it *settlement* rather than a discretionary lever.

## 5. eUTxO grounding (settled background)

Carried from the companion feasibility research; these are the load-bearing constraints, not open questions.

- **Predicates are reactive, not autonomous.** CIP-113 `transfer_logic` / `issuance_mint` / `third_party` validators are withdraw-zero stake validators that run only when a submitted transaction spends a token UTxO, returning approve/reject against that transaction. There is no scheduler. "Automatically on an event" always means *a keeper detects the event and submits a transaction*, which the predicate then approves. This bounds every P2 claim: the trigger is keeper-driven.
- **No escape from programmable custody (drives P3).** All programmable tokens are custodied at the shared `programmable_logic_base`; the global validator forbids moving them to non-programmable addresses. So graduation (P3) cannot be an in-place unwrap; it must **burn the CIP-113 token and mint a separate native token**, which is the source of the identity/fungibility problem in Q-GRAD-1.
- **`ThirdPartyAct` is real and seizure-capable.** The `third_party` redeemer permits a designated script to force transfer / freeze / burn with no owner authorization; seized tokens stay within the base. This is the mechanism behind P2's "third-party rules," and any design that holds tokens in a contract is inherently seizure-exposed (Q-RULE-2).
- **Oracles are pull-based.** eUTxO has no authoritative current time and no push; event data arrives as UTxOs a consuming validator reads and must itself check for freshness against the fact's `created_at`. Every P2 rule that depends on external data is oracle-dependent and pull-based.
- **Contention is per-design.** Per-holder conditioning is cheap and contention-free; any shared-state UTxO (a resolution node, a registry node) serializes and can be griefed, worst for time-sensitive triggers. Which cases are per-holder vs shared-state is a design axis (Q-CONTENTION-1).

## 6. Scope

**In scope:** discrete-event conditioning (P2), permissive transfer (P1), and event-gated graduation/burn (P3), for per-holder instruments with a settlement end state.

**Out of scope (non-goals):**
- Transfer permissioning (KYC/AML, blacklists) - separate CIP-113 profile.
- Continuous / autonomous / "real-time" behaviour - impossible on eUTxO; every state change is keeper-submitted.
- Pooled cross-protocol capital management (yield aggregation, auto-compounding, hedging, dynamic collateralization) - belongs to the Tokenized Vault candidate; CIP-113 is not the enabler there.

## 7. Open questions

- **Graduation identity (Q-GRAD-1):** given P3 is burn+remint under a different policy, how do we preserve asset identity / fungibility and any DEX pool or price history across graduation? Global one-time flip of the whole supply (clean identity, coordinated moment) vs per-holder migration (flexible, but a split supply during transition)?
- **Graduation authority & direction (Q-GRAD-2):** P3 removes protections. Should it be gated strictly by the same event condition the rules enforce (only once `fully_vested` / `resolved` is on-chain true), so it cannot be used as a discretionary rug?
- **Event-rule interface (Q-RULE-1):** the concrete pluggable P2 hook shape; reuse the `Credential` pattern; reference-input reads that respect the `ARCHITECTURE.md` predicate rules (no global tx-shape assumptions).
- **Seizure posture (Q-RULE-2):** which cases legitimately want `ThirdPartyAct` (regulated recall, dispute resolution) vs must disavow it (holder assurance), and how is the `third_party` script's key/governance model disclosed?
- **Base layer (Q-BASE-1):** should the minimal version use plain native tokens (P2/P3 only, no CIP-113 base), reserving the CIP-113 base for cases needing metadata/registry?
- **Contention (Q-CONTENTION-1):** classify each catalog case as per-holder (no contention) vs shared-state (may need batching, cf. #8).
- **Split-out (Q-SPLIT-1):** should P3 (graduation) be its own catalog item shared with the Token Wrapper / Receipt candidate and the CIP-113-to-native proxy (#1), rather than living only inside this substandard?

## 8. Dependency map

- **Oracle / event source** (candidate) - P2 event facts.
- **CIP-113 programmable tokens** (#2) - P1 base + P2 predicates.
- **CIP-113-to-native interaction / proxy** (#1) - closest relative of P3; graduation is its permanent, event-gated form.
- **Token Wrapper / Receipt** (candidate) - shares the lock/mint/redeem shape with P3.
- **Escrow (#6), Prediction Markets (#7, #8), Linear Vesting (#3)** - consumers expressible as this substandard.
- **A DEX / Atomic Swap (#5)** - pricing venue for tradable cases.

## 9. Prior art

- **Other chains:** Gnosis Conditional Tokens Framework / Polymarket (complete-set outcome tokens); tokenized bonds (World Bank bond-i, Centrifuge); Ribbon oTokens (ERC-20 options); Toucan (retire-and-burn carbon credits); Etherisc (parametric insurance via Chainlink); ERC-5643 (subscription NFTs); dynamic NFTs; Superfluid / Sablier (streaming); Royal / Story Protocol (royalty streams). Transfer-permissioned counterexample: ERC-3643 / T-REX. Framing parallel: ERC-3643 `canTransfer` and ERC-4626 are both pure compliance/interface layers that generate no yield, exactly as CIP-113 approves/rejects but manages nothing.
- **Cardano ecosystem:** CIP-113 (programmable tokens, the base), CIP-68 (metadata, #15), CIP-86 (NFT metadata update oracles) as a P2 pattern; oracle providers Charli3, Orcfax, Pyth as event sources; live conditioning-adjacent precedent in Liqwid qTokens (appreciating-exchange-rate model) and Djed / Indigo (keeper + oracle driven).
- **Internal:** feasibility research on the six "CIP-113 unlocked" use cases (event-triggered = per-UTxO conditioning, feasible, keeper-driven); the #1 / #2 investigations reached the same "CIP-113 adds value at the per-UTxO-conditioning layer" conclusion.
