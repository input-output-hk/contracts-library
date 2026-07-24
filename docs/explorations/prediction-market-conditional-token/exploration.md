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

To take a position, lock 1 unit of collateral and mint a *complete set* of outcome tokens (1 YES + 1 NO). A complete set can always be burned back for 1 collateral. A **time-gated minting policy** enforces complete-set mint/burn during the betting window; after the cutoff, no new tokens can be minted. An external **resolution authority** declares the winning outcome via a single **beacon-authenticated outcome UTxO** (written by a pluggable `outcome_credential`, read as a reference input). After resolution, the winning token redeems for 1 collateral and the losing token for 0. You express a view by holding/selling the side you want; your *odds* are the price at which you traded the token, **locked in at trade time**.

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

- **Oracle** (building-block candidate): reports the outcome. Abstracted via a `Credential` (§5).
- **Outcome-token minting policy**: enforces complete-set mint/burn and time-gating. Can be built on **CIP-113 programmable tokens** (candidate) for permissioning/metadata, or plain native tokens for the minimal version.
- **A pricing/liquidity venue** for entering/exiting: an **Order-book DEX** or **AMM DEX** (candidates), or **peer-to-peer** via **Atomic Swap** (#5) for illiquid markets. Trading is *delegated*, not reimplemented.
- **Multisig** (candidate): optional, when the outcome authority is a committee.

### 3.5 Downsides

Not self-contained: a market with no liquidity venue and no counterparties is not tradable. Leans on several other catalog items. This is precisely the gap the parimutuel sibling fills.

## 4. Design Sketch

Market identity, authorization, and lifecycle parameters live in UTxO datums; the market address, setup fee, and per-redemption fee are compile-time validator parameters. Both validators are multivalidators, so only **2 scripts serve all markets** regardless of count, but each market is deployed with its own address and fee configuration baked into the scripts.

```aiken
pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type TokenInfo {
  asset: AssetClass,
  amount: Int,
}

pub type Winner {
  Yes
  No
  Draw
}

// Outcome validator(protocol_address: Address, setup_fee: TokenInfo)

pub type OutcomeDatum {
  market_id: ByteArray,
  cutoff: Int,
  winner: Option<Winner>,
  outcome_credential: Credential,
  resolution_timeout: Int,
  claim_deadline: Int,
  collateral: TokenInfo,
}

pub type OutcomeRedeemer {
  Resolve { winner: Winner }
}

pub type BeaconMintAction {
  MintBeacon { market_id: ByteArray }
}

// Redemption validator(protocol_address: Address, market_fee: TokenInfo)

pub type RedemptionDatum {
  market_id: ByteArray,
  beacon_policy: PolicyId,
}

pub type RedemptionRedeemer {
  RedeemWinner { output_index: Int }
  BurnCompleteSet { output_index: Int }
  ClaimTimeout { output_index: Int }
  ClaimDraw { output_index: Int }
  SweepResidual { output_index: Int }
}

pub type MintAction {
  MintSet { market_id: ByteArray }
  BurnSet { market_id: ByteArray }
  BurnWinner { market_id: ByteArray }
}
```

### Outcome validator

Receives `protocol_address: Address` (where fees are sent) and `setup_fee: TokenInfo` (fee charged when a market is created/initialized).

#### Mint

- `MintBeacon { market_id }`: mints exactly 1 beacon token per market.

#### Spend

- `Resolve { winner }`: requires `outcome_credential` authorization; preserves the beacon token and all datum fields except `winner` in a continuation UTxO, setting `winner` to `Some(winner)`.

### Redemption validator

Receives `protocol_address: Address` (where fees are sent) and `market_fee: TokenInfo` (fee charged per redemption action).

#### Mint

- `MintSet { market_id }`: mints `N` YES + `N` NO tokens only while the validity range ends `<= cutoff`. Token names encode `market_id` (e.g., `YES_<market_id>`) so tokens are non-fungible across markets sharing the same mint policy.
- `BurnSet { market_id }`: burns k YES + k NO tokens.
- `BurnWinner { market_id }`: burns k winning tokens.

#### Spend

- `RedeemWinner { output_index }`: reads the outcome UTxO via reference input; verifies the beacon token's actual policy matches `datum.beacon_policy`, cross-checks `market_id`, extracts the `collateral` unit from the outcome datum, requires `winner == Some(winning_side)` (with `winning_side != Draw` and matching the token side), and pays 1 collateral per winning token burned. `output_index` tags the exact payout output (anti-double-satisfaction).
- `BurnCompleteSet { output_index }`: reads the outcome UTxO via reference input to obtain the collateral unit; requires `winner == None` (pre-resolution); burns equal YES + NO for 1 collateral each.
- `ClaimTimeout { output_index }`: valid only while the transaction validity range starts after `resolution_timeout` and ends before `claim_deadline`. Reads the outcome UTxO via reference input to obtain the collateral unit. Burns any single YES and/or NO tokens (no complete-set requirement) and pays 0.5 collateral per token burned, deducted from the redemption UTxO's value. Produces a continuation redemption UTxO with the remaining collateral. With N YES + N NO tokens minted, burning m YES + n NO yields (m+n)/2 collateral returned; the residual is N − (m+n)/2.
- `ClaimDraw { output_index }`: analogous to `ClaimTimeout`, but valid only when the outcome is a `Draw` and the transaction validity range ends before `claim_deadline`.
- `SweepResidual { output_index }`: valid only when the transaction validity range starts after `claim_deadline`. Reads the outcome UTxO via reference input. Sends the entire remaining balance of the redemption UTxO to `protocol_address` (validator parameter). Destroys the redemption UTxO (no continuation).

## 5. Resolution: pluggable authority via `Credential`

No contract hardcodes *how* resolution is decided. The authority is a Cardano `Credential` supplied by the consumer (pubkey -> satisfied by a signature; script -> satisfied by a forwarded withdraw-zero validator, letting a committee/DAO/optimistic-oracle stand in). Same mechanism as Escrow (#6) and ARCHITECTURE.md §3.

The resolution result lives in a **beacon-authenticated UTxO** read by settlement as a **reference input**. Beacons are minted once at market genesis and parked, then moved into the resolution UTxO when the authority approves (one-shot by construction, no betting contention).

For conditional-token settlement this needs only a **single** `outcome_credential` attesting the winner in a single beacon-authenticated outcome UTxO. That is all settlement needs: there is no separate multiplier to attest (contrast the parimutuel sibling, which requires a second solvency-critical credential).

The outcome UTxO also serves as the reference input for any transaction that requires the collateral unit. All redemption spend paths read the outcome UTxO via reference input to obtain the `collateral` field from the outcome datum, so the redemption script can verify the collateral asset class and amount without hardcoding them in validator parameters.

## 6. Cross-cutting security must-fixes

The hazards are the familiar ones — double satisfaction on the payout path (same class as Atomic Swap #5), position authenticity (the mint must be time-gated so no one fabricates a winning position post-resolution), and resolution liveness (timeout fallback). No on-chain aggregation or solvency attestation is needed.

| Risk | Severity | Mitigation | Status |
|---|---|---|---|
| Double satisfaction | **High** | Tagged-output design on redemption path | Designed (§4) |
| Position fabrication | **High** | Time-gated minting policy (§3.1) | Designed |
| Stuck funds (missing resolution) | Medium | Timeout fallback to half-claim via `ClaimTimeout`; residual sweeps to market after `claim_deadline` | Designed (§4); incentives open (Q-ORACLE-1) |
| Composability breakage | Medium | Reference-input resolution; no global transaction-shape assertions | Designed |

- **Position/ticket authenticity.** Positions must be authenticated tokens minted under a policy that is **time-gated to the betting window**, so no one can fabricate a winning position after resolution. Here this is the complete-set mint. Without it, an attacker mints a "winning" position post-outcome and drains funds.
- **Double satisfaction** on the payout path (same class as Atomic Swap #5): one output must not be credited to two redemptions.
- **Resolution liveness.** If resolution never arrives, funds must not be stuck: after `resolution_timeout`, `ClaimTimeout` allows single-token holders to claim 0.5 collateral per token; after `claim_deadline`, `SweepResidual` sends the remainder to `protocol_address`. Ties into resolver incentives (Q-ORACLE-1).
- **Composability (ARCHITECTURE.md).** Settlement must assert only properties of its **own** UTxOs, never the total value/inputs/outputs of the transaction. The reference-input resolution design (§5) keeps reads composable.

## 7. Outcome scope

- **Binary (YES/NO):** v1.
- **Categorical (N discrete outcomes):** a cheap generalization of the settlement layer (binary = N=2). `side`/`winner` becomes an index `0..N-1`; a complete set mints one token per outcome; the winning token redeems for 1 collateral. To investigate. Note the flagship platforms instead express multi-outcome as **linked binary markets** (Polymarket's NegRisk), so "binary + a linking convention" may be the more familiar shape.

## 8. Open questions

| ID | Question | Current leaning | Status |
|----|----------|-----------------|--------|
| Q-SCOPE-1 | Confirm binary or categorical (§7) for v1. | binary v1 | open |
| Q-ORACLE-1 | What makes the resolution authority report honestly + on time (bond/slash, reputation)? | tbd | open |
| Q-DISPUTE-1 | Optimistic resolution window? (Outcome disputes are tractable.) | outcome-only dispute | open |
| Q-LIFECYCLE-1 | Cancellation: creator cancels a zero-position market? Refund-all before cutoff? | allow both | open |
| Q-FEES-1 | Creator/protocol fees, and resolver incentive; where the cut goes. | tbd | open |

## 9. Dependency map

- **Oracle** (candidate): resolution feed. Abstracted via `Credential` (§5).
- **Multisig / Smart wallet** (candidate): committee/DAO resolver = a script credential.
- **CIP-113 programmable tokens** (candidate): outcome tokens (or native tokens for the minimal version).
- **Order-book DEX / AMM DEX** (candidates) and **Atomic Swap** (#5): pricing/liquidity. Deliberately *composed*, not rebuilt.
- **Escrow** (#6): shares the pluggable-`Credential` resolution approach.
- **`authorization.ak`**: shared Credential authorization logic (already exists in on-chain library). Reused by the outcome validator.

## 10. Prior art

- **Polymarket:** CLOB over Gnosis Conditional Token Framework (1 YES + 1 NO redeem for 1 USDC); UMA optimistic oracle. Not parimutuel. Multi-outcome = linked binary markets via NegRisk. **This is the direct analogue of the design here.**
- **Kalshi:** CFTC-regulated exchange; binary event contracts settling $1/$0 on a CLOB. (Third Circuit 2026: such contracts are swaps under the CEA; CFTC jurisdiction preempts state gambling law.)
- **Augur:** decentralized reporting + dispute rounds.
- **Omen / LMSR:** AMM-priced markets.
- **Resolution feeds:** Charli3, Orcfax, Pyth.

## 11. Regulatory / non-goal note

Prediction markets are regulated (as gambling and/or as derivatives) in many jurisdictions. The library ships **code only**; we never operate a market or custody funds (PRD §3.2). The fixed-payout event-contract shape reads as a derivative, but compliance is the deployer's concern.

## 12. Composability check against ARCHITECTURE.md

The settlement layer asserts only properties of its own UTxOs and explicitly consumer-provided references:

| Assertion | Violates architecture? |
|-----------|----------------------|
| UTxO datums match expected structure | No — own UTxO property |
| Mint policy burns/mints correct token quantities | No — own UTxO property |
| Outcome reference input is present with valid datum | No — explicit related UTxO reference |
| Collateral unit matched to outcome reference input datum | No — own-UTxO assertion, collateral identity from outcome datum |
| Authorization on outcome UTxO spend (Resolve) | No — own UTxO authorization |
| Validity range is before betting deadline | No — explicit time-dependent constraint |
| **Not asserted:** total tx inputs/outputs, total value, signatory set beyond required authorization, unrelated UTxOs | — |

The reference-input resolution pattern (§5) satisfies ARCHITECTURE.md §1.1 (validators must not assert global TX properties) and §3 (pluggable `Credential` authorization).

## 13. Recommendation

**Verdict: Implement now.** Design is sketched for a binary v1. Core is small, security-critical but audit-tractable, and composes with existing catalog items. Implementation uses datum-level parameterization: 2 on-chain multivalidator scripts (Outcome with `spend` + `mint`, Redemption with `spend` + `mint`) serve any number of markets.
