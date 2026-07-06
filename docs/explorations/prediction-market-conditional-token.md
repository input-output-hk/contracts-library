# Exploration: Prediction Market - Conditional-Token Settlement

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage is deferred to team discussion.
>
> **Sibling investigation:** [`prediction-market-parimutuel.md`](prediction-market-parimutuel.md) explores the pooled alternative. The two split a single earlier exploration; this document is the **recommended default** and the parimutuel one is the no-liquidity alternative for illiquid markets. §3 of each carries the head-to-head comparison.

## 1. Use case

A market where participants stake on the outcome of a future event, and winners are paid from the losing side once the event resolves. Roles: **bettors/traders** (take positions on outcomes), a **resolution authority** (declares the winning outcome), and optionally a **market creator** (opens the market and sets its parameters/fees).

Lifecycle: open -> take positions (until a cutoff) -> event occurs -> external resolution declares the outcome -> winners collect / losers forfeit, with an undecidable event refunding everyone.

**Category:** DeFi. **Outcome scope:** binary (YES/NO).

## 2. Core framing: settlement vs pricing

A prediction market is two separable concerns, and keeping them separate is the key to a clean, composable design (it is how the flagship platforms (e.g., Polymarket) work):

- **Settlement layer**: how staked positions convert into payouts once the outcome is known. This is the security-critical core and the natural library primitive. **This document is a settlement layer.**
- **Pricing / liquidity layer**: how a participant enters or exits a position and at what odds (order book, AMM, pooled, or peer-to-peer).

Polymarket, for instance, is a **conditional-token settlement layer** (Gnosis CTF) plus a **central-limit-order-book** for pricing; the two are independent contracts. This split is the entire reason to prefer the conditional-token approach: it standardizes only the settlement layer and **composes** the pricing layer from existing catalog items rather than duplicating them.

## 3. Mechanism

### 3.1 How it works

To take a position, lock 1 unit of collateral and mint a *complete set* of outcome tokens (1 YES + 1 NO). A complete set can always be burned back for 1 collateral. After resolution, the winning token redeems for 1 collateral and the losing token for 0. You express a view by holding/selling the side you want; your *odds* are the price at which you traded the token, **locked in at trade time**.

### 3.2 Why this is the recommended default

- **Known, fixed payout** (1 winning token = 1 collateral); answers the biggest parimutuel complaint (payout unknown until close, see the sibling doc). Positions are **tradable/exitable** on any market that lists the token.
- **Minimal trust and minimal on-chain complexity.** Payout solvency is guaranteed *by construction*: every winning token is backed by collateral from some complete set. There is no payout ratio to compute, so no `S_yes/S_no` totals, no fold, no solvency attestation. The resolution authority reports **only the binary outcome**.
- **Regulation-friendlier framing.** The fixed-$1 "event contract" shape is what Kalshi operates as a CFTC-regulated derivative (not gambling). For us this matters only as a connotation, since we ship code and never operate (PRD §3.2), but it is the shape teams can plausibly frame as a regulated instrument.
- **Matches demand.** It matches why the category is popular (known payout, tradable positions) and removes the hardest on-chain problems by delegating pricing to a DEX.

### 3.3 Comparison against the parimutuel alternative

| Mechanism | Payout known at bet time | Liquidity/counterparty needed | Trust surface | Key dependencies | Best fit |
|---|---|---|---|---|---|
| **Conditional-token + DEX** (this doc) | Yes (trade price) | Yes (a venue) | Outcome only | Oracle, token policy (CIP-113), a DEX / Atomic Swap | Liquid markets; aligned with demand + regulation |
| **Parimutuel, trusted `m`** (sibling) | No | No | Outcome + `m` (solvency) | Oracle, Multisig, batcher | Illiquid / long-tail markets |
| **Parimutuel, trustless `m`** (sibling) | No | No | Outcome only | + linked-list fold, batcher | As above, minimal trust, high complexity |
| **Native AMM/CLOB** | Yes | Yes (LPs/makers) | Outcome only | - | Rejected: duplicates DEX candidates |


**Rejected: native continuously-priced market.** Building an AMM or order book *into* the prediction-market contract just reimplements the **AMM DEX** / **Order-book DEX** candidates. We prefer to **compose** those with this settlement layer rather than duplicate them. Not pursued as a standalone mechanism.

**Current recommendation:** default to this conditional-token settlement layer, and keep the parimutuel design as the no-liquidity alternative for illiquid markets. The parimutuel's one durable advantage is needing no liquidity.

### 3.4 Dependencies

- **Oracle** (building-block candidate): reports the outcome. Abstracted via a `Credential` (§4).
- **Outcome-token minting policy**: enforces complete-set mint/burn and time-gating. Can be built on **CIP-113 programmable tokens** (candidate) for permissioning/metadata, or plain native tokens for the minimal version.
- **A pricing/liquidity venue** for entering/exiting: an **Order-book DEX** or **AMM DEX** (candidates), or **peer-to-peer** via **Atomic Swap** (#5) for illiquid markets. Trading is *delegated*, not reimplemented.
- **Multisig** (candidate): optional, when the outcome authority is a committee.

### 3.5 Downsides

Not self-contained: a market with no liquidity venue and no counterparties is not tradable. Leans on several other catalog items. This is precisely the gap the parimutuel sibling fills.

## 4. Resolution: pluggable authority via `Credential`

No contract hardcodes *how* resolution is decided. The authority is a Cardano `Credential` supplied by the consumer (pubkey -> satisfied by a signature; script -> satisfied by a forwarded withdraw-zero validator, letting a committee/DAO/optimistic-oracle stand in). Same mechanism as Escrow (#6) and ARCHITECTURE.md §3.

The resolution result lives in a **beacon-authenticated UTxO** read by settlement as a **reference input**. Beacons are minted once at market genesis and parked, then moved into the resolution UTxO when the authority approves (one-shot by construction, no betting contention).

For conditional-token settlement this needs only a **single** `outcome_credential` attesting the winner in a single beacon-authenticated outcome UTxO. That is all settlement needs: there is no separate multiplier to attest (contrast the parimutuel sibling, which requires a second solvency-critical credential).

## 5. Cross-cutting security must-fixes

- **Position/ticket authenticity.** Positions must be authenticated tokens minted under a policy that is **time-gated to the betting window**, so no one can fabricate a winning position after resolution. Here this is the complete-set mint. Without it, an attacker mints a "winning" position post-outcome and drains funds.
- **Double satisfaction** on the payout path (same class as Atomic Swap #5): one output must not be credited to two redemptions.
- **Void / invalid outcome.** The authority can attest `Void`; everyone refunds by burning their complete set. Must exist.
- **Resolution liveness.** If resolution never arrives, funds must not be stuck; likely a timeout fallback to Void/refund. Ties into resolver incentives (Q-ORACLE-1).
- **Composability (ARCHITECTURE.md).** Settlement must assert only properties of its **own** UTxOs, never the total value/inputs/outputs of the transaction. The reference-input resolution design (§4) keeps reads composable.

## 6. Outcome scope

- **Binary (YES/NO):** v1.
- **Categorical (N discrete outcomes):** a cheap generalization of the settlement layer (binary = N=2). `side`/`winner` becomes an index `0..N-1`; a complete set mints one token per outcome; the winning token redeems for 1 collateral. To investigate. Note the flagship platforms instead express multi-outcome as **linked binary markets** (Polymarket's NegRisk), so "binary + a linking convention" may be the more familiar shape.

## 7. Open questions

| ID | Question | Current leaning | Status |
|----|----------|-----------------|--------|
| Q-SCOPE-1 | Confirm binary or categorical (§6) for v1. | binary v1 | open |
| Q-ORACLE-1 | What makes the resolution authority report honestly + on time (bond/slash, reputation)? | tbd | open |
| Q-DISPUTE-1 | Optimistic resolution window? (Outcome disputes are tractable.) | outcome-only dispute | open |
| Q-LIFECYCLE-1 | Cancellation: creator cancels a zero-position market? Refund-all before cutoff? | allow both | open |
| Q-FEES-1 | Creator/protocol fees, and resolver incentive; where the cut goes. | tbd | open |


## 8. Dependency map

- **Oracle** (candidate): resolution feed. Abstracted via `Credential` (§4).
- **Multisig / Smart wallet** (candidate): committee/DAO resolver = a script credential.
- **CIP-113 programmable tokens** (candidate): outcome tokens (or native tokens for the minimal version).
- **Order-book DEX / AMM DEX** (candidates) and **Atomic Swap** (#5): pricing/liquidity. Deliberately *composed*, not rebuilt.
- **Escrow** (#6): shares the pluggable-`Credential` resolution approach.

## 9. Prior art

- **Polymarket:** CLOB over Gnosis Conditional Token Framework (1 YES + 1 NO redeem for 1 USDC); UMA optimistic oracle. Not parimutuel. Multi-outcome = linked binary markets via NegRisk. **This is the direct analogue of the design here.**
- **Kalshi:** CFTC-regulated exchange; binary event contracts settling $1/$0 on a CLOB. (Third Circuit 2026: such contracts are swaps under the CEA; CFTC jurisdiction preempts state gambling law.)
- **Augur:** decentralized reporting + dispute rounds.
- **Omen / LMSR:** AMM-priced markets.
- **Resolution feeds:** Charli3, Orcfax, Pyth.

## 10. Regulatory / non-goal note

Prediction markets are regulated (as gambling and/or as derivatives) in many jurisdictions. The library ships **code only**; we never operate a market or custody funds (PRD §3.2). The fixed-payout event-contract shape reads as a derivative, but compliance is the deployer's concern.
