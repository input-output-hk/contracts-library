# Exploration: P2P Swaps - Distributed Order Book

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage is deferred to team discussion.
>
> **Sibling investigation:** [Order-book DEX - Decentralized Limit-Order Book (#18)](https://github.com/input-output-hk/contracts-library/issues/18) explores the shared-address, GeniusYield `PartialOrder` variant of the same use case. The two split a single "order book" concern into two on-chain settlement mechanisms. This document is the **distributed / batcherless** alternative (modelled on [cardano-swaps](https://github.com/fallen-icarus/cardano-swaps), Apache-2.0). §3.3 carries the head-to-head against the sibling.

## 1. Use case

An on-chain limit-order venue where a maker locks an offered asset at a stated price and anyone may fill the order, wholly or partially, by paying the maker at (or better than) that price. Roles: **makers** (post resting orders), **takers** (fill them), and optional **arbitrageurs / routers** (discover complementary orders, and route across other venues, for profit). No privileged operator.

Lifecycle: create order -> rest until filled or cancelled -> takers fill (partial fills recreate a smaller resting order) -> maker closes or updates the remainder at any time. Matching is permissionless; no batcher is required for the protocol to function.

**Category:** DeFi.

## 2. Core framing: three separable concerns

An order-book venue is three concerns, and the distinctive claim of this variant is that all three can be made non-custodial and operator-free:

- **Settlement**: how a resting order is consumed and the maker is paid. The security-critical core and the library primitive.
- **Discovery**: how open orders are found on-chain without a hosted indexer.
- **Matching**: who assembles fill transactions, and whether they can be trusted.

The sibling (#18) answers these with a shared script address, a per-order NFT plus an off-chain indexer, and a reference matchmaker bot. This variant answers them with **sovereign addresses**, **beacon-token discovery**, and **batcherless permissionless execution**. The settlement mechanics also differ (stateless ratio fills vs. an explicit `remaining` counter), which is why this is worth exploring as a distinct primitive rather than a parameterisation of #18.

## 3. Mechanism

### 3.1 How it works

Verified against the cardano-swaps Aiken source.

**Sovereign addresses.** There is no shared script address. Each maker's orders sit at *their own* address, formed as `(universal spending-script hash, maker's own staking credential)`. Every order across all makers shares the same spending script but differs by staking credential, so the maker keeps custody and retains staking / delegation rights over locked funds. This is a real custody advantage and the sharpest departure from #18.

**Beacon-token discovery.** Each order UTxO carries beacon tokens with deterministic names, so open orders are found by asset query alone, with no hosted indexer:

- One-way: offer beacon `sha2_256("01" ++ offerPolicy ++ offerName)`, ask beacon `sha2_256("02" ++ askPolicy ++ askName)`, pair beacon `sha2_256(offer ++ ask)`.
- Two-way: `asset1` / `asset2` / pair beacons over lexicographically-sorted assets (direction-independent).

Beacons do double duty: order **identity** and **discovery**. They scale with trading *pairs*, not with the number of orders.

**Stateless, ratio-based partial fills.** There is no `remaining` field and no fill counter. The public `Swap` redeemer requires, per order UTxO:

1. A corresponding output at the **same address** carrying the **same beacons**.
2. Output datum equal to the input datum **except** `prev_input := Some(input_ref)`.
3. Price satisfied as `offer_taken * price_num <= ask_given * price_den` (rational, no division, rounds in the maker's favour).
4. Value purity: only the offer asset may leave, only the ask asset may enter; ADA is deposit-only when neither leg is ADA (so min-UTxO can always be topped up).

"Remaining amount" is simply the residual offer asset left in the recreated UTxO. Partial vs. complete fill is emergent from how much is taken, not a datum mode. Most of #18's partial-fill accounting question (a `remaining` decrement, a fill counter, rounding direction) dissolves under this model.

**`prev_input` is the double-satisfaction guard.** The corresponding output must record the exact `input_ref` of the order it settles. Input references are globally unique, so one output can never satisfy two orders. The check asserts only about the contract's *own* output, never about total transaction inputs / outputs / value, so it satisfies ARCHITECTURE.md §1.1 without assuming transaction shape.

**Batcherless and composable.** `Swap` is public: anyone executes, no privileged batcher. Owner-only actions (create, close, price update) are gated by the address's staking credential via redeemers that delegate to the beacon script running as a minting policy (create / close, mints or burns beacons) or as a staking validator (price-only update, no re-mint). Arbitrageurs are *optional* value-adders who capture the spread and can chain many swaps across pairs (and external AMMs) atomically in one transaction.

**Two-way swaps (optional).** A single UTxO can carry two prices (`asset1Price`, `asset2Price`) and be filled in either direction, giving native dual-price market-making. This directly addresses the classic order-book weakness (a book goes quiet in thin markets) without pulling in a shared-pool AMM.

### 3.2 Why this is worth exploring alongside #18

- **Operator-free by construction.** No indexer to host and no batcher to run, which fits the "we ship code, we do not operate a service or custody funds" stance (PRD §3.2.1) more tightly than the sibling. The reference off-chain piece is an *optional* arbitrageur / router, not required infrastructure.
- **Answers #18's hardest open questions up front.** `prev_input` is a concrete, composable answer to double satisfaction (#18 Q-DS-1); the stateless ratio invariant largely removes the partial-fill accounting question (#18 Q-FILL-1); batcherless execution is a concrete answer to trustless matching (#18 Q-MATCH-1).
- **Cleaner eUTxO fit.** Strict per-UTxO validation with no shared state and no transaction-shape assertions is a near-exact match for ARCHITECTURE.md §1.1. Contention is per-single-order only (two takers racing the same order; one wins per block), never global.
- **Custody + delegation.** Sovereign addresses keep the maker's staking rights on locked funds, which no shared-address design can offer.
- **Reusable, permissively licensed prior art.** cardano-swaps is Apache-2.0 with the on-chain layer already in Aiken, so it is a re-implementable reference against our spec, not a clean-room guess.

### 3.3 Comparison against the sibling (#18)

| Dimension | Distributed swaps (this doc) | Shared-address `PartialOrder` (#18) |
|---|---|---|
| Order custody | Sovereign address; maker keeps staking / delegation | Shared script address |
| Discovery | Beacon tokens, indexer-free | Per-order NFT + off-chain indexer |
| Order identity | Beacon set (per pair) | One-shot NFT (per order) |
| Partial fills | Stateless ratio invariant; recreate same datum | `remaining` + fill counter, explicit decrement |
| Double satisfaction | `prev_input = Some(input_ref)`, composable | Per-order output tagging (open, #18 Q-DS-1) |
| Matching | Batcherless, permissionless, cross-venue arb | Reference matchmaker bot |
| Passive liquidity | Two-way swaps (dual-price market-making) | Out of v1 scope |
| Fees | None in core (spread accrues to arbers) | Maker/taker flat + percentage |
| Owner auth | Staking credential of the address | `owner` key in datum |
| Off-chain requirement | Optional arber / router | Matchmaker expected |

Neither is strictly better on every axis. The sibling's `remaining` counter makes a single order's fill history explicit and is closer to what integrators coming from GeniusYield expect; its shared address concentrates discovery. This variant trades those for operator-free discovery, custody, and a lighter on-chain model. The fee axis is a design choice, not a fixed property (see §5, Q-FEES-1).

### 3.4 Dependencies

- **Beacon minting / staking policy**: the discovery and owner-authorisation mechanism. Part of the contract, not an external dependency.
- **Off-chain arbitrageur / router** (in scope, optional to run): discovers complementary orders and assembles fills. v1 targets a correct, minimal matcher, explicitly not a competitive smart order router.
- **AMM DEX (#17)** and the sibling **Order-book DEX (#18)**: a router can aggregate across all three; not required.
- **Prediction Market (#7)**: a natural pricing / exit venue for outcome tokens, the same role the sibling plays.

### 3.5 Downsides

- **No passive liquidity in the one-way core**: a book still needs counterparties present, unless two-way swaps are included (§3.1).
- **Beacon surface**: adds a minting / staking-script surface and a naming convention the off-chain must reproduce exactly; more moving parts than a single NFT.
- **Scattered orders**: sovereign addresses spread a pair's orders across many addresses, which is exactly what beacons exist to re-aggregate, but it is a different mental model for integrators.
- **No built-in fee rail**: deployers who want a fee-bearing venue must add the optional fee layer (Q-FEES-1).

## 4. Authorization: owner via a `Credential`

Owner-only actions (close, update) are gated in cardano-swaps by the address's staking credential. A staking credential may itself be a **script hash**, so a multisig / DAO / smart-wallet owner already works without changing the spending script. This composes with the library's experimental pluggable-`Credential` authorizer (ARCHITECTURE.md §3) instead of hardcoding an `owner` public key in the datum: pubkey credential -> satisfied by a signature; script credential -> satisfied by the forwarded script. Whether to model owner authority as the address's staking credential (cardano-swaps' shape) or as a datum-level `Credential` (the sibling's shape) is Q-AUTH-1.

## 5. Cross-cutting security must-fixes

- **Double satisfaction.** One output must not settle two orders. The `prev_input = Some(input_ref)` tag is the proposed guard; confirm it holds when a single transaction fills many orders and when composed with other library validators, without assuming transaction shape (ARCHITECTURE.md §1.1).
- **Partial-fill soundness.** The recreated order must preserve every datum field except `prev_input`, keep its beacons, and satisfy the price ratio with rounding in the maker's favour. Only the offer asset may leave; only the ask asset may enter.
- **Dust / griefing.** A taker may take almost all of the offer and leave a dust remainder, but must pay proportionally, so this is not economic griefing (the maker was paid fairly and can close the dust UTxO). An optional `min_fill` / `min_remaining` floor would prevent unspendable dust but costs some composability (a transaction-shape-adjacent assertion); default is to omit it. This is Q-FILL-1.
- **Order authenticity.** A fill must act on a real order, established by the required beacon set in the input and the recreated output. A look-alike UTxO without the correct beacons is not a valid order.
- **Owner-only close / update.** Reclaiming or repricing the remaining offer must require the owner authority (§4) and must burn / re-mint beacons correctly on structural changes.
- **Expiry / lifecycle.** Optional expiration (aligned to 1-minute multiples, checked against the transaction validity range's upper bound) stops execution after expiry while still allowing the owner to close. No third-party refund is required.
- **Composability (ARCHITECTURE.md).** Settlement asserts only about its own input and corresponding output, never the transaction's total value / inputs / outputs. The per-UTxO model and `prev_input` guard are what keep this true.

## 6. Scope

- **One-way swaps (limit orders):** v1.
- **Two-way swaps (dual-price market-making):** a natural extension that adds passive liquidity; investigate whether it belongs in v1 or a later variant.
- **Out of scope:** operating a hosted matching service or custodying funds (PRD §3.2.1); a production-grade router with advanced / programmable order types (stop, iceberg, conditional) and sophisticated cross-venue aggregation. v1 aims for a correct, simple matcher, not a competitive SOR.

## 7. Open questions

| ID | Question | Current leaning | Status |
|----|----------|-----------------|--------|
| Q-CUSTODY-1 | Sovereign addresses vs. a single shared script address. | sovereign (custody + delegation + operator-free discovery) | open |
| Q-DS-1 | Does `prev_input = Some(input_ref)` fully prevent double satisfaction under N-way fills and composition? | yes, and it is composable | open |
| Q-FILL-1 | Stateless ratio fills: any need for a `min_fill` / `min_remaining` floor against dust? | omit floor unless a concrete grief is found | open |
| Q-BEACON-1 | Beacon discovery vs. per-order NFT; is the extra minting-policy surface worth the indexer-free property? | beacons (fits PRD §3.2.1) | open |
| Q-AUTH-1 | Owner authority as the address's staking credential vs. a datum-level pluggable `Credential`. | staking credential, but confirm §3 composition | open |
| Q-FEES-1 | Zero-fee core (spread to arbers) vs. an optional pluggable fee layer for fee-bearing deployers. | zero-fee core + optional fee layer | open |
| Q-TWOWAY-1 | Include two-way swaps in v1 for passive liquidity, or defer to a later variant. | tbd | open |
| Q-MATCH-1 | How minimal is the reference arber / router (naive scan + single-pair matching vs. a small selection heuristic)? | minimal v1 | open |
| Q-PROV-1 | Re-implement the design against our spec vs. vendor and adapt the Apache-2.0 Aiken source. | re-implement, spec-first (ARCHITECTURE.md §2.3) | open |

## 8. Dependency map

- **Beacon minting / staking policy** (part of this contract): discovery + owner authorisation.
- **Multisig / Smart wallet (#11)**: an owner authority expressed as a script staking credential (§4).
- **AMM DEX (#17)** and **Order-book DEX (#18)**: a router aggregates across venues; not required.
- **Prediction Market (#7)**: pricing / exit venue for outcome tokens.
- **Atomic Swap (#5)**: the named all-or-nothing swap that a single openly-takeable order generalises.

## 9. Prior art

- **cardano-swaps** (fallen-icarus, Apache-2.0): the direct model for this variant. Distributed / sovereign-address swaps, beacon discovery, stateless ratio fills, `prev_input` double-satisfaction guard, batcherless execution, one-way and two-way swaps. On-chain in Aiken; Haskell CLI off-chain (does not carry over, we would ship MeshJS / Tx3 builders and a reference arber).
- **GeniusYield**: the shared-address `PartialOrder` model, explored in the sibling (#18).
- **MuesliSwap**: decentralized order book with rewarded matchmakers and on-chain partial fills.
- **Axo**: programmable / advanced order types, the direction for later variants.
- **Internal**: generalises **Atomic Swap (#5)**; complements **AMM DEX (#17)** and the sibling **Order-book DEX (#18)**; closes a pricing-venue dependency for **Prediction Market (#7)**.
