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
├── lakefile.toml            # depends on Blaster + PlutusCore + CardanoLedgerApi
├── lean-toolchain           # pinned Lean version
├── flake.nix                # elan + Z3 4.15.2 + gawk
├── justfile                 # build -> flats -> verify pipeline
├── scripts/
│   └── annotate-blaster-logs.awk
├── Formal.lean              # root; imports every contract aggregator
└── Formal/
    ├── Common.lean          # shared `validatorAccepts` / `validatorRejects`
    └── Vesting/
        ├── Linear.lean      # aggregator for the vesting/linear contract
        └── Linear/
            ├── Spec.lean          # pure model: `vested`, datum encoding (no UPLC)
            ├── Completeness.lean  # spec ⇒ accepts (§8); `#import_uplc`s the flat
            ├── Soundness.lean     # accepts ⇒ spec (§9) + shared context scaffold
            └── Robustness.lean    # rejection theorems incl. no-double-satisfaction
```

Each contract gets its own `Completeness`/`Soundness`/`Robustness` under its
folder, because the properties differ per contract. The layout follows
`francolq/aiken-good-practices` (`order-book/verify`). Every theorem carries a
doc comment citing the spec section it discharges (e.g. `§9 B1`).

## Prerequisites

The easiest path is **Nix** — `flake.nix` provides the whole toolchain:

```bash
cd formal
nix develop      # shell with elan (Lean v4.24.0) + Z3 4.15.2 + gawk
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
just deps        # once: fetch Blaster + PlutusCore + CardanoLedgerApi (lake update)
just verify      # build -> flats -> lake build (annotated)
```

Or directly, inside the dev shell:

```bash
cd formal
# (in `nix develop`, or with elan + z3 on PATH)
lake update      # fetch Blaster + PlutusCore + CardanoLedgerApi
lake build       # type-check all modules and run every `blaster` proof
```

A failing `blaster` goal can be debugged with its options, e.g.
`blaster (verbose: 1)` or `blaster (gen-cex: 1)` to print a counterexample.

## Status

**Proved (pure-arithmetic core, `Spec.lean`).** The schedule function and its
§3.3 / §9 boundary lemmas. These do not touch UPLC:

| Theorem | Spec |
|---|---|
| `vested_preStart` | §9 B3 — nothing vests before `start` |
| `vested_full` | §8.2, I4 — everything vests at/after `end` |
| `vested_le_total` | §9 B1 — never releases more than the total |
| `vested_nonneg` | bounds `vested` below by 0 |
| `required_nonneg` | dual of B1 — remainder constraint satisfiable |
| `vested_mono` | §9 B2 — `vested` non-decreasing in `now` |

(All `by blaster`; unverified here because the toolchain/Z3 build runs on your
machine, not in this scaffold.)

**Scaffolded, NOT yet proved (`Completeness`/`Soundness`/`Robustness`).** The
transaction-level theorems are *stated* against the compiled validator
(`Completeness.lean` loads it with `#import_uplc`), with the datum/redeemer
encoding mirroring `onchain/lib/vesting/types.ak`. Their proofs are `sorry` with
explicit `TODO`s, and a few modeling pieces are open. Per project policy,
nothing here is presented as proved until it actually checks.

Open `TODO`s blocking real proofs (all flagged in-file):

- **validity-range encoding** — `Soundness.validRangeData` must encode the
  interval `[now, +∞)` as the validator reads it (§5.2). Currently `sorry`.
- **script-credential auth** — only the verification-key branch is modeled;
  the withdraw-0 (script) branch via `txInfoWdrl` is TODO.
- **value-bundle generality** — modeled per single asset; generalize to an
  arbitrary bundle.
- **`CardanoLedgerApi.V3` field names** — taken from the reference project;
  verify against the actual library on first build.
- **no-double-satisfaction** (`Robustness`, §5.1/I2) — needs a ≥2-input,
  shared-datum context; the headline property and the hardest to model.

The continuation datum is intentionally left **arbitrary** in Soundness and
Robustness (the reference fixes it — `-- THIS IS CHEATING`), so the proofs must
*derive* datum-reproduction rather than assume it.
