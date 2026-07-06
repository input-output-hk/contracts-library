# Exploration: Atomic Swap

> Status: **Exploring** (pre-triage). Working design log, not a spec. Triage is deferred to team discussion.
>
> **Scope:** Trustless two-party exchange with no third-party arbiter. The conditional/arbitrated release case (delivery attestation, milestone refunds) is tracked in #6.

## 1. Use case

A creator (Alice) locks an offered asset (token A) on-chain while demanding another (token B); a taker (Bob) provides the demanded asset (token B) and takes the offered one (token A) in a single transaction. Both parties settle atomically with no third party and no external state.

**Lifecycle:** Lock -> Complete or Cancel.

**Category:** DeFi. **Scope:** v1 supports one maker and one taker per UTxO. Partial fills are out of scope (pushing them toward the order-book DEX candidate).
