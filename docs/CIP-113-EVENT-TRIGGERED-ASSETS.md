# CIP-113 Substandard Architecture: Event-Triggered Assets (P1 / P2 / P3)

## 1. Modular Architecture Overview

### P1: Permissive-Transfer Base
P1 defines a CIP-113 programmable token that imposes **no transfer rules**. Token movement occurs as freely as a native Cardano asset, avoiding any transfer-gating logic.

### P2: Event-Rule Hooks
Pluggable event hooks process discrete eUTXO reference inputs (e.g. Orcfax, Charli3, or Pyth oracle state). Event triggers update token state or release tranche balances without requiring continuous rebalancing.

### P3: Graduation / Unwrap Path
One-way exit converting CIP-113 tokens into plain native assets:
- **Burn-and-Remint Mechanics**: Issuer minting policy burns the CIP-113 asset and mints un-wrapped native tokens upon event maturity.
- **Per-Holder Migration**: Supports self-service per-holder graduation where the token holder signs the transaction, preventing forced un-wrapping.

## 2. Answers to Open Questions
- **Q-GRAD-1 (Asset Identity)**: Per-holder migration with deterministic burn-and-remint maintains verifiable identity across liquidity pools.
- **Q-GRAD-2 (Authority Gating)**: Holders must sign graduation transactions to prevent un-wrapping without holder consent.
