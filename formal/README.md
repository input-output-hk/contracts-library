# Formal proofs

Machine-checked proofs of the contract **specifications** under [`../specs`](../specs).
This is a fourth artifact alongside `onchain/`, `offchain/`, and `specs/`: the
proofs are *about the spec* (the source of truth), not about any one
implementation. See [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §2.

Proofs are written in [Lean 4](https://lean-lang.org/) and discharged with
[Lean-Blaster](https://github.com/input-output-hk/Lean-blaster), an SMT (Z3)
backend invoked via the `blaster` tactic.

## Layout

```
formal/
├── lakefile.toml            # depends on Blaster
├── lean-toolchain           # pinned Lean version
├── Formal.lean              # root; imports every contract's proof module
└── Formal/
    └── Vesting/
        └── Linear.lean      # linear-vesting model + proofs
```

Each spec gets one module under `Formal/`, mirroring `specs/`. Every theorem
carries a doc comment citing the spec section it discharges (e.g. `§9 B1`).

## Prerequisites

The easiest path is **Nix** — `flake.nix` provides the whole toolchain:

```bash
cd formal
nix develop      # drops you in a shell with elan (Lean v4.24.0) + Z3 4.15.2
```

`flake.nix` pins Z3 to exactly `4.15.2` and provides `elan`, which fetches the
Lean toolchain named in `lean-toolchain` on first use. Inputs are pinned in
`flake.lock`.

Without Nix, install manually:

- **Lean 4 `v4.24.0`** (pinned in `lean-toolchain`). Use
  [`elan`](https://github.com/leanprover/elan) so Lake fetches the matching
  toolchain automatically.
- **Z3 `4.15.2`** on `PATH`. Build from source per the
  [Blaster README](https://github.com/input-output-hk/Lean-blaster);
  `z3 --version` should report `Z3 version 4.15.2`.

## Build

The `justfile` in this directory drives the whole pipeline (compile Aiken →
dump UPLC → encode to flat → check proofs):

```bash
cd formal
just deps        # once: fetch Blaster (lake update)
just verify      # build -> flats -> lake build
```

Or directly, inside the dev shell:

```bash
cd formal
# (in `nix develop`, or with elan + z3 on PATH)
lake update      # fetch Blaster
lake build       # type-check all modules and run every `blaster` proof
```

> **Note.** `just flats` already encodes the compiled validator to
> `Scripts/<module>_spend.flat`, but the proof modules here still target the
> spec *model* (`vested`), not that bytecode. Wiring a proof module to load the
> flat is the bridge to verifying the actual on-chain code — see Roadmap.

A green `lake build` means every property in scope is proved. A failing
`blaster` goal can be debugged with its options, e.g. `blaster (verbose: 1)` or
`blaster (gen-cex: 1)` to print a counterexample.

## What is proved

Currently the **pure-arithmetic core** of linear vesting
([`specs/vesting/linear-vesting.md`](../specs/vesting/linear-vesting.md) §3.3
and the §9 boundary lemmas), in `Formal/Vesting/Linear.lean`:

| Theorem | Spec |
|---|---|
| `vested_preStart` | §9 B3 — nothing vests before `start` |
| `vested_full` | §8.2, I4 — everything vests at/after `end` |
| `vested_le_total` | §9 B1 — never releases more than the total (no over-release) |
| `vested_nonneg` | bounds `vested` below by 0 |
| `required_nonneg` | dual of B1 — the remainder constraint is satisfiable |
| `vested_mono` | §9 B2 — `vested` is non-decreasing in `now` |

## Roadmap

The transaction-level properties — completeness `C0`–`C8` (§8) and soundness
`R1`–`R7` (§9) — are **not yet modeled**. They require:

- a model of the transaction (inputs, continuing outputs, validity range,
  signatories, withdrawals), the `VestingDatum`, and the `Credential`
  authorization predicate;
- the `k`-scaled continuation/no-double-satisfaction argument (§5.1, I2);
- the `accepts(tx, datum, redeemer) ⟺ Φ` characterization, split into the
  completeness (`⇐`) and soundness (`⇒`) directions.

These build on the arithmetic core proved here.
