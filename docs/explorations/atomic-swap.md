# Exploration: Atomic Swap

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage deferred to team discussion.
>
> **Scope:** Trustless two-party exchange with no third-party arbiter. One owner locks asset A; a resolver provides asset B and receives A in return via a tagged output.

## 1. Use case

An owner locks an offered asset (asset A) at the order script address. A resolver later provides a demanded asset (asset B) and receives asset A. The settlement is atomic within one transaction.

**Lifecycle:** Lock -> Resolve or Close.
**Category:** DeFi. **Scope:** v1 supports one owner and one resolver per order. Partial fills are out of scope.

## 2. Mechanism

A single eUTxO holds the order terms as its datum. The owner locks the offered assets at the order script address. Two actions are possible:

- **Resolve:** A resolver consumes the order UTxO and creates a tagged output at the same order script address that satisfies the order terms. The tagged output must carry the demanded assets and the updated datum. The original locked asset A leaves the order output and goes to the resolver; the tagged output holds the demanded asset B plus at least the original lovelace.
- **Close:** The order UTxO is consumed with no tagged output requirements, provided the transaction is signed by the owner.

No protocol-managed liquidity, no price oracle. The contract is purely a validator over its own UTxOs.

## 3. Design sketch

### 3.1 Datum and redeemer types

```aiken
use aiken/crypto.{VerificationKeyHash}

pub type OrderDatum {
  owner: VerificationKeyHash,
  amount: Int,
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type OrderRedeemer {
  Resolve(Int)
  Close
}
```

`owner` is a `VerificationKeyHash` that identifies who created the order. `amount`, `policy_id`, and `asset_name` describe the demanded asset and quantity. The output designated by the redeemer's index acts as the tagged output for this order and prevents double satisfaction (§5.1).

## 4. Validation walkthrough

**Resolve.**

1. Identifies the order's own input and script hash.
2. Extracts the tagged output at `out_ix` and requires it to be an inline-datum output with no reference script (a deliberate design choice).
3. Checks the tagged output address matches the order script address.
4. Checks the tagged output value keeps at least the original lovelace, contains at least the demanded asset quantity, and has exactly two asset classes (lovelace and demanded asset). This shape also ensures the originally locked asset A has left the order output.
5. Checks the tagged output datum is the original datum.
6. Rejects resolving an already-resolved order: a valid `Resolve` can only be applied when the order has not been resolved before (e.g., the input still carries the original datum).

**Close.** Requires the owner's signature. The validator does not constrain where the locked assets go.

## 5. Complexity and risk read

### 5.1 Double satisfaction

**The attack.** Two identical order UTxOs are consumed in one transaction. If the validator checks only that "some output contains the demanded assets," a single funded output could satisfy both orders.

**Mitigation: tagged outputs.** The `Resolve(Int)` redeemer designates exactly one output index as the tagged output for that order. Each resolved order must point to its own output, so two orders cannot satisfy themselves from a single output.

### 5.2 Other considerations

- **`Close` requires owner signature.** Only the order owner can close the order.
- **Exact value shape.** The tagged output must have exactly two asset classes (lovelace and demanded asset). This implicitly forces the originally locked asset A to leave the order output when resolving.
- **No time-lock.** The order can be resolved or closed at any time.

### 5.3 Risk summary

| Risk | Severity | Mitigation | Status |
|------|----------|------------|--------|
| Double satisfaction | **High** | Tagged outputs (§5.1) | Designed |
| Unauthorized Close | Low | Owner signature required | Mitigated |
| Tagged output value shape too strict | Low | Exact two-asset requirement | Documented |
| Min-ADA | Low | Ledger-enforced; off-chain builder responsibility | Documented |

## 6. Composability check against ARCHITECTURE.md

The validator asserts only properties of its own input and the designated tagged output. It does not constrain total inputs, outputs, mints, withdrawals, or signatories beyond the owner signature on `Close`. However, the strict two-asset tagged output requirement may limit composability with other contracts.

## 7. Dependency map

**None beyond the standard library.** No oracle, external batcher, or cross-contract reads. The validator depends only on Aiken's standard library modules for value and transaction inspection.

## 8. Open questions

| ID | Question | Current leaning | Status |
|----|----------|-----------------|--------|
| Q-AUTH-1 | Should Close require owner signature? | Yes; confirmed as design | Confirmed |
| Q-ASSET-1 | Should tagged output allow more than two asset classes? | Strict shape is simple but limits composability | Open |
| Q-PARTIAL-1 | Partial fills? | Out of scope; push to order-book DEX | Confirmed |
| Q-DS-1 | Double-satisfaction mitigation confirmed? | Redeemer designates a unique tagged output index per order | Designed |

## 9. Recommendation: Deferred

**Verdict: Deferred in favor of Escrow (#6).**

The order-based swap covers the same lock/resolve/close lifecycle as a degenerate escrow case (no arbiter, payment-is-the-condition) while also supporting arbitrated release. When a dedicated swap is needed, it should derive from escrow base logic rather than be built independently.
