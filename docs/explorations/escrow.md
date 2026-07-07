# Escrow Protocol — Exploration

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage deferred to team discussion.

## 1. Lightweight design sketch

### Datum/Redeemer shape

Core skeleton of the escrow state:

- **Depositor**: party locking the assets (Alice)
- **Beneficiary**: party receiving assets on success (Bob)
- **Condition**: the release authority—arbiter key, oracle reference, or deadline
- **Optional timeout**: fallback deadline (e.g., for arbiter unavailability)

Redeemer variants:

- `Release`: to beneficiary when the condition holds
- `Refund`: to depositor (on timeout or mutual cancel)

### Validation predicate

Core logic:

1. **Release path**: verify the condition is satisfied (arbiter signature, oracle result, or other proof); assert beneficiary is paid
2. **Refund path**: verify timeout elapsed or refund authorization; assert depositor is repaid
3. Both paths must ensure the full amount is released and no partial leakage

## 2. Complexity / risk read

### Trust model

Condition sources under consideration:

- **Single arbiter signature**: trust the arbiter to approve release (most common in the wild)
- **M-of-N arbiter multisig**: distribute trust across a panel (requires Multisig contract integration)
- **Oracle feed**: condition sourced from an oracle (requires Oracle contract integration and external dependency)
- **Plain deadline**: time-based refund (no third party, but inflexible)

### Arbiter-failure analysis

Risk scenario: **malicious or absent arbiter**. If the arbiter refuses to act, the funds may be locked indefinitely.

Mitigation: Require an **optional timeout**; if elapsed without arbiter action, fall back to refund

## 3. Composability check against ARCHITECTURE.md

- **Double satisfaction** can be mitigated using tagged outputs, without introducing global assumptions about transaction shape.
- **Deferring condition source** to a separate withdrawal script (e.g., Multisig or Oracle) allows modular composition as in ARCHITECTURE.md §3.
- **Open questions**:
  - Should a "no arbiter, payment-is-the-condition" configuration collapse to Atomic Swap (#5), or remain a distinct contract? (Q-BOUNDARY-1)
  - Does the condition source (especially an oracle reference) fit the predicate rules in `ARCHITECTURE.md` without global assumptions about transaction shape? (Q-COMPOSE-1)

## 4. Open questions

| ID | Question | Current leaning | Status |
| ---- | ---------- | ----------------- | -------- |
| Q-TRUST-1 | Which condition sources do we support: single arbiter signature, M-of-N arbiter multisig, oracle feed, plain deadline? | defer to separate withdrawal script and compose with multisig/oracle scripts | open |
| Q-LIVENESS-1 | How do we handle a malicious or absent arbiter? | require timeout fallback (refund or release) | open |
| Q-DISPUTE-1 | Single arbiter vs. a panel, and how ties are broken. | tbd | open |
| Q-REFUND-1 | Who can trigger a refund and when (deadline reached, mutual cancel)? | tbd | open |
| Q-BOUNDARY-1 | Should a "no arbiter, payment-is-the-condition" configuration collapse to #5, or stay a distinct contract? | confirm and record boundary with Atomic Swap | open |
| Q-COMPOSE-1 | Does the condition source (especially an oracle reference) fit the predicate rules in `ARCHITECTURE.md` without global assumptions about transaction shape? | must satisfy ARCHITECTURE composability rules | open |

## 5. Prior art

- **Cardano ecosystem**: escrow and marketplace validators in the wild, frequently using a single arbiter key or an M-of-N multisig as the release authority.
- **Other chains**: OpenZeppelin's `Escrow` / `ConditionalEscrow` / `RefundEscrow` utilities are the closest direct analogues; HTLC covers the hash/time-conditioned subset.
- **Internal**: shares the lock-then-release skeleton with Linear Vesting and Atomic Swap (#5), but the release condition is external rather than a counterparty payment. Likely depends on the Multisig and Oracle contracts for its richer condition sources.

## 6. Recommendation: Recommendation: Deferred

Verdict: Deferred in favor of Order Book (#18).
