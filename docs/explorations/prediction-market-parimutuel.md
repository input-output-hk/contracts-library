# Exploration: Prediction Market - Parimutuel Pooled

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage is deferred to team discussion.
>
> **Sibling investigation:** [`prediction-market-conditional-token.md`](prediction-market-conditional-token.md) explores the conditional-token settlement layer, which is the **recommended default**.

## 1. Use case

A market where participants stake on the outcome of a future event, and winners are paid from the losing side once the event resolves. Roles: **bettors** (stake on outcomes), a **resolution authority** (declares the winning outcome and, in the trusted-`m` variant, the pool multiplier), and optionally a **market creator** (opens the market and sets its parameters/fees).

Lifecycle: open -> stake into a pool (until a cutoff) -> event occurs -> external resolution declares the outcome -> winners split the pool pro-rata / losers forfeit, with an undecidable event refunding everyone.

**Category:** DeFi. **Outcome scope:** binary (YES/NO).

## 2. Core framing: settlement vs pricing

A prediction market is two separable concerns:

- **Settlement layer**: how staked positions convert into payouts once the outcome is known.
- **Pricing / liquidity layer**: how a participant enters or exits a position and at what odds.

The distinguishing feature of the parimutuel design is that it **collapses these two concerns into one self-balancing pool**: there is no separate pricing venue and no counterparty. That is its whole reason to exist, and the reason it survives where the conditional-token design (which requires an external liquidity venue) cannot.

## 3. Mechanism

### 3.1 How it works

All stakes on each outcome pool together. When YES wins, YES bettors split the entire pool pro-rata: a stake `s` pays `s · m` where `m = (S_yes + S_no) / S_yes`. The multiplier depends on the *final* pool composition.

### 3.2 Why keep this alternative

- **Needs no liquidity and no counterparty.** The pool is self-balancing. An empty order book yields no market; a parimutuel pool still functions. This fits **thin-liquidity and long-tail events**, which is a realistic concern on Cardano.
- **Fully self-contained**: no DEX dependency, simplest to ship end-to-end.

### 3.3 Comparison against the conditional-token default


| Mechanism | Payout known at bet time | Liquidity/counterparty needed | Trust surface | Key dependencies | Best fit |
|---|---|---|---|---|---|
| **Conditional-token + DEX** (sibling) | Yes (trade price) | Yes (a venue) | Outcome only | Oracle, token policy (CIP-113), a DEX / Atomic Swap | Liquid markets; aligned with demand + regulation |
| **Parimutuel, trusted `m`** (this doc) | No | No | Outcome + `m` (solvency) | Oracle, Multisig, batcher | Illiquid / long-tail markets |
| **Parimutuel, trustless `m`** (this doc) | No | No | Outcome only | + linked-list fold, batcher | As above, minimal trust, high complexity |
| **Native AMM/CLOB** | Yes | Yes (LPs/makers) | Outcome only | - | Rejected: duplicates DEX candidates |


**Current recommendation:** the sibling conditional-token settlement layer is the default; this parimutuel design is retained as the no-liquidity alternative. Its one durable advantage is needing no liquidity venue.

### 3.4 Downsides

- **Payout is unknown at bet time** (the multiplier is only fixed at close), odds drift as money arrives, late bettors are advantaged, and there is **no early exit**. This is a documented reason platforms move away from parimutuel (e.g. Manifold).
- Computing `m` trustlessly on-chain is hard (see §6), so v1 would **delegate `m` to a trusted authority**, which introduces a solvency-critical trust assumption.

### 3.5 Dependencies

- **Oracle** + **Multisig** (candidates): resolution authority, for both the outcome and (in the trusted-`m` variant) the multiplier. Two credentials (§4).
- **Batcher** (off-chain order pattern, as in SundaeSwap/Minswap): for payout contention at scale (§6.1).
- **Trustless-`m` variant only:** a **linked-list + fold** aggregation plus a batcher for insert liveness (§6.2). Large added surface.

## 4. Resolution: pluggable authority via `Credential`

No contract hardcodes *how* resolution is decided. The authority is a Cardano `Credential` supplied by the consumer (pubkey -> satisfied by a signature; script -> satisfied by a forwarded withdraw-zero validator, letting a committee/DAO/optimistic-oracle stand in). Same mechanism as Escrow (#6) and ARCHITECTURE.md §3.

The resolution result lives in **beacon-authenticated UTxO(s)** read by settlement as **reference inputs**. Beacons are minted once at market genesis and parked, then moved into the resolution UTxO when the authority approves (one-shot by construction, no betting contention). The full beacon machinery is load-bearing here specifically because the parimutuel case needs **two** decoupled resolution UTxOs.

The parimutuel design needs **two** credentials, because `m` is a separate, solvency-critical claim (and `m` is outcome-independent: the pool freezes at cutoff, the outcome only selects which side's multiplier applies):

- `outcome_credential` -> a UTxO with `winner : Yes | No | Void`.
- `m_credential` -> a UTxO with the frozen-pool figure (encoding TBD, Q-CRED-2).

Two decoupled one-shot UTxOs; payout reads both (Void refund needs only the outcome). They may point at the same authority. The `m_credential` can be swapped for a fold-verifier to make `m` trustless (§6.2) without touching the outcome authority.

## 5. Cross-cutting security must-fixes

- **Position/ticket authenticity.** Positions must be authenticated tokens minted under a policy that is **time-gated to the betting window**, so no one can fabricate a winning position after resolution. Here this is the bet ticket. Without it, an attacker mints a "winning" position post-outcome and drains funds.
- **Double satisfaction** on the payout path (same class as Atomic Swap #5): one output must not be credited to two redemptions.
- **Void / invalid outcome.** The authority can attest `Void`; everyone refunds their own stake. Must exist.
- **Resolution liveness.** If resolution never arrives (or only one of the two attestations does), funds must not be stuck; likely a timeout fallback to Void/refund. Ties into resolver incentives (Q-ORACLE-1, Q-CRED-3).
- **Composability (ARCHITECTURE.md).** Settlement must assert only properties of its **own** UTxOs, never the total value/inputs/outputs of the transaction. The reference-input resolution design (§4) keeps reads composable.
- **Parimutuel-only:** minimum bet size (anti dust-grief when winners consume many losing UTxOs); floored payout arithmetic (never over-pay -> stay solvent), with a defined sweep for residual dust.

## 6. Implementation notes

### 6.1 Contention

Design the trusted-`m` parimutuel so betting has **no shared state**: each bet is an independent, fresh UTxO authenticated by a time-gated mint (deadline is a policy parameter, so minting consumes no shared UTxO and is fully parallel). Contention then appears only at **payout** (winners drawing from losing UTxOs), which is benign (post-close, no odds drift) and absorbed by a **batcher** (request UTxOs serviced in bulk; the validator makes the batcher trustless for *safety*, so it can only fail to serve, never steal, with a timeout escape for liveness).

### 6.2 Trustless `m` via linked-list fold

To compute `m` on-chain without trusting an authority, bets must form a **closed, enumerable set**. The canonical pattern (Anastasia `aiken-design-patterns`, Plutonomicon `assoc.md`) is a **token-secured sorted linked list**: each node is an NFT-authenticated UTxO with `{key, value, next}`; the minting policy only issues a node NFT if the head or an existing node is spent, so no node can exist outside the structure. A **fold** then walks the list at close, accumulating `{S_yes, S_no}`; **completeness is guaranteed** because finalization is only allowed at the tail and the pointer chain cannot skip a node. 

For our case the fold can read nodes as **reference inputs** (leaving the ticket intact for payout) and can be **permissionless** (deterministic, cannot divert funds). Cost: insertion contention + off-chain neighbor lookup (a batcher job), a multi-tx fold, and a large audit surface. This is why v1 delegates `m` and treats the fold as a later, swappable `m_credential` implementation (Q-MECH-3).

### 6.3 `m`-datum encoding (open, bench during exploration)

Carry pool totals `{S_yes, S_no}` (rounding centralized in payout, exact match to the fold's output) vs. pre-divided rationals `{m_yes, m_no}` (authority does the rounding). Totals are cleaner and outcome-symmetric, but bench the on-chain arithmetic cost of both (Q-CRED-2).

## 7. Outcome scope

- **Binary (YES/NO):** v1.
- **Categorical (N discrete outcomes):** a cheap generalization (binary = N=2). `winner` becomes an index `0..N-1`; the pool figure becomes N totals; payout draws from any non-winning position (losing collateral is fungible). Note the flagship platforms instead express multi-outcome as **linked binary markets** (Polymarket's NegRisk), so "binary + a linking convention" may be the more familiar shape.

## 8. Open questions

| ID | Question | Current leaning | Status |
|----|----------|-----------------|--------|
| Q-SCOPE-1 | Confirm binary vs categorical cheap (§7) for v1 | binary v1 | open |
| Q-ORACLE-1 | What makes the resolution authority report honestly + on time (bond/slash, reputation)? | tbd | open |
| Q-DISPUTE-1 | Optimistic resolution window? (Outcome disputes are tractable; a wrong-`m` dispute needs the pool sum, so it is not.) | outcome-only dispute | open |
| Q-LIFECYCLE-1 | Cancellation: creator cancels a zero-position market? Refund-all before cutoff? | allow both | open |
| Q-TIMING-1 | Position cutoff strictly before the outcome is knowable (invariant), enforced via minting validity range. | validity-range gated | open |
| Q-FEES-1 | Creator/protocol fees, and resolver incentive; where the cut goes. | tbd | open |
| Q-CRED-2 | `m`-datum encoding: totals vs pre-divided rationals; bench arithmetic (§6.4). | totals, bench both | open |
| Q-CRED-3 | Missing-attestation liveness: timeout -> Void if one attestation never arrives. | timeout -> Void | open |
| Q-MECH-3 | Linked-list fold as a swappable trustless-`m` credential (§6.2). | tracked, post-v1 | open |


## 9. Dependency map

- **Oracle** (candidate): resolution feed. Abstracted via `Credential` (§4).
- **Multisig / Smart wallet** (candidate): committee/DAO resolver = a script credential.
- **Batcher** (off-chain order pattern, as in SundaeSwap/Minswap): payout contention (§6.1).
- **Escrow** (#6): shares the pluggable-`Credential` resolution approach.

## 10. Prior art

- **Manifold:** moved off a dynamic-parimutuel design because traders did not know their payout at bet time. **The central cautionary tale for this design.**
- **Augur:** decentralized reporting + dispute rounds.
- **Polymarket:** CLOB over Gnosis Conditional Token Framework; UMA optimistic oracle. **Not** parimutuel (the sibling design's analogue), included for contrast.
- **Kalshi:** CFTC-regulated exchange; binary event contracts settling $1/$0 on a CLOB. Not parimutuel.
- **Cardano:** oracle providers Charli3, Orcfax (resolution feeds); batcher/order pattern in SundaeSwap, Minswap (contention); Anastasia linked-list/fold and Plutonomicon `assoc.md` (aggregation).

## 11. Regulatory / non-goal note

Prediction markets are regulated (as gambling and/or as derivatives) in many jurisdictions. The library ships **code only**; we never operate a market or custody funds (PRD §3.2). The parimutuel pool shape reads as gambling, but compliance is the deployer's concern.
