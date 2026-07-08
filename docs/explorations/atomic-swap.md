# Exploration: Atomic Swap

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage deferred to team discussion.
>
> **Scope:** Trustless two-party exchange with no third-party arbiter. One maker locks asset A; a taker provides asset B and receives A in return.

## 1. Use case

A maker locks an offered asset (asset A) at the swap script address. A taker later provides a demanded asset (asset B) and receives asset A. The settlement is atomic within one transaction.

**Lifecycle:** Lock -> Resolve or Cancel.
**Category:** DeFi. **Scope:** v1 supports one maker and one taker per order. Partial fills are out of scope.

## 2. Mechanism

- A single eUTxO holds the swap terms as its datum. The maker locks the offered assets at the swap script address. Two actions are possible:

- **Resolve:** A taker consumes the swap UTxO by paying the demanded asset to the maker.
- **Cancel:** The swap UTxO is consumed provided the transaction is signed by the maker.

No protocol-managed liquidity, no price oracle. The contract is purely a validator over its own UTxOs.

## 3. Design sketch

### 3.1 Datum and redeemer types

```aiken
use aiken/crypto.{VerificationKeyHash}
use cardano/assets.{AssetName, PolicyId}

pub type OrderDatum {
  maker: VerificationKeyHash,
  amount: Int,
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type OrderRedeemer {
  Resolve(Int)
  Cancel
}
```

`maker` is a `VerificationKeyHash` that identifies who created the swap. `amount`, `policy_id`, and `asset_name` describe the demanded asset and quantity. The output designated by the redeemer's index acts as the tagged output for this swap and prevents double satisfaction (§4.1).

## 4. Complexity and risk read

### 4.1 Double satisfaction

**The attack.** Two identical swap UTxOs are consumed in one transaction. If the validator checks only that "some output contains the demanded assets," a single funded output could satisfy both swaps.

**Mitigation: tagged outputs.** The `Resolve(Int)` redeemer designates exactly one output index as the tagged output for that swap. Each resolved swap must point to its own output, so two swaps cannot satisfy themselves from a single output.

### 4.2 Other considerations

- **`Cancel` requires maker signature.** Only the swap maker can cancel the swap.
- **Exact value shape.** The swap UTxO must have exactly two asset classes (lovelace and the offered asset).
- **No time-lock.** The swap can be resolved or closed at any time.

### 4.3 Risk summary

| Risk | Severity | Mitigation | Status |
| ---- | -------- | ---------- | ------ |
| Double satisfaction | **High** | Tagged outputs (§4.1) | Designed |
| Unauthorized Cancel | Low | Maker signature required | Mitigated |
| Min-ADA | Low | Ledger-enforced; off-chain builder responsibility | Documented |

## 5. Composability check against ARCHITECTURE.md

The validator asserts only properties of its own input and the designated tagged output. It does not constrain total inputs, outputs, mints, withdrawals, or signatories beyond the maker signature on `Cancel`.

## 6. Dependency map

**None beyond the standard library.** No oracle, external batcher, or cross-contract reads. The validator depends only on Aiken's standard library modules for value and transaction inspection.
 > Note: the `is_authorized` function in `onchain/lib/authorization.ak` can be used to check that the maker signature is present on `Cancel`.

## 7. Open questions

| ID | Question | Current leaning | Status |
| -- | -------- | --------------- | ------ |
| Q-AUTH-1 | Open offer (any taker) vs. named taker | Open offer for v1 | Open |
| Q-CANCEL-1 | Maker-only Cancel sufficient, or add an optional deadline after which the maker can always reclaim? | Maker-only for v1 | Open |
| Q-ASSET-1 | One asset per side for v1, or allow bundles (multiple assets per leg)? | Single asset for v1 | Open |
| Q-PARTIAL-1 | Partial fills? | Out of scope; push to order-book DEX | Confirmed |
| Q-DS-1 | Double-satisfaction mitigation confirmed? | Redeemer designates a unique tagged output index per order | Designed |

## 8. Recommendation: Deferred

**Verdict: Deferred in favor of Escrow (#6).**

The order-based swap covers the same lock/resolve/cancel lifecycle as a degenerate escrow case (no arbiter, payment-is-the-condition) while also supporting arbitrated release. When a dedicated swap is needed, it should derive from escrow base logic rather than be built independently.
