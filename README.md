# ContractsLibrary

[![CodeQL](https://github.com/input-output-hk/contracts-library/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/input-output-hk/contracts-library/actions/workflows/github-code-scanning/codeql)
[![CI](https://github.com/input-output-hk/contracts-library/actions/workflows/ci.yml/badge.svg)](https://github.com/input-output-hk/contracts-library/actions/workflows/ci.yml)

**_A library of standardized, reusable smart contracts for Cardano._**

ContractsLibrary provides battle-tested, ready-to-use contract implementations, shipped as **on-chain + off-chain pairs** with a decoupled formal **spec** and machine-checked **formal proofs**. The goal is to reduce the time and risk of building on Cardano, especially for developers new to the ecosystem.

## Why

The EVM ecosystem matured in part because OpenZeppelin gave developers vetted, reusable contracts. Cardano lacks an equivalent: teams repeatedly re-implement the same primitives (vesting, escrow, token standards, AMMs), each time re-incurring design and security risk.

Existing Cardano libraries operate at a *lower* level of abstraction (on-chain utilities and generic patterns). **ContractsLibrary operates at the use-case level**: complete contracts, both on-chain and off-chain. We are very grateful to and stand on the shoulders of libraries like [vodka](https://github.com/sidan-lab/vodka) and [Anastasia Labs' design-patterns](https://github.com/Anastasia-Labs/design-patterns).

## How you use it

Every contract supports a layered consumption model:

1. **Use:** Supply parameters to a finished contract and ship.
1. **Compose:** Import lower-level validation functions and off-chain helpers to build something new.
1. **Fork:** Copy the module(s) and modify for your needs.

You can choose how you want to use this library depending on your needs

> TODO: Add proper instructions when ready

## Anatomy of a contract

Each contract ships as four parts:

| Part | Location | Role |
|---|---|---|
| **On-chain** | `onchain/` | Aiken validation logic the ledger enforces. The only part that carries security. |
| **Off-chain** | `offchain/` | Transaction builders developers call. The primary developer-facing API. |
| **Spec** | `specs/` | Implementation-independent description of behavior. The source of truth. |
| **Formal proofs** | `formal/` | Machine-checked Lean 4 proofs *about the spec* (completeness, soundness, robustness). |


Validators are written as well-behaved predicates that avoid global assumptions about transaction shape, so contracts compose freely in shared transactions. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the composability rules.

## Repository structure

```
onchain/      Aiken workspace (lib/<contract>/, validators/)
offchain/
  meshjs/     MeshJS implementations
  tx3/        Tx3 implementations
specs/        decoupled per-contract specifications
formal/       Lean 4 proofs of the specs (Lean-Blaster / Z3)
docs/         PRD, ARCHITECTURE, contributor docs
```

## Contract catalog

The full, status-tracked catalog lives in the [PRD](docs/PRD.md#7-contract-catalog). Current In progress, Ready-to-audit, or Audited/Verified contracts:

| Contract | Category | Status | Spec |
|---|---|---|---|
| Linear vesting | DeFi | In progress | [spec](specs/vesting/linear-vesting.md) |


More candidates (escrow, AMM, CIP-68, programmable tokens, multisig, DAO, …) are explored and triaged in the PRD.

## Getting started

The on-chain layer is an Aiken workspace:

```sh
cd onchain
aiken build    # compile validators
aiken check    # run tests
```

The off-chain layer provides TypeScript builders (MeshJS) and Tx3 implementations under `offchain/`.

## Documentation

- [Product Requirements (PRD)](docs/PRD.md) — what we ship, goals, catalog.
- [Architecture](docs/ARCHITECTURE.md) — composability conventions every
  contract follows.
- [Formal proofs](formal/README.md) — machine-checked Lean 4 proofs of the
  specs, plus the build pipeline and `blaster` tractability notes.

## License

**Apache-2.0** for all artifacts: on-chain, off-chain, specs, and docs.
