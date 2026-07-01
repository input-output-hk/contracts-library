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
├── justfile                 # build -> verify pipeline
├── scripts/
│   └── annotate-blaster-logs.awk
├── Formal.lean              # root; imports every contract aggregator
└── Formal/
    ├── Common.lean          # shared `validatorAccepts` / `validatorRejects`
    └── Vesting/
        ├── Linear.lean      # aggregator for the vesting/linear contract
        └── Linear/
            ├── Spec.lean          # pure model: `vested`, datum encoding (no UPLC)
            ├── Completeness.lean  # spec ⇒ accepts (§8); `#import_blueprints` the validator
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

The `justfile` in this directory drives the whole pipeline (compile Aiken to a
CIP-57 blueprint → check proofs):

```bash
cd formal
just deps        # once: fetch Blaster + PlutusCore + CardanoLedgerApi (lake update)
just verify      # build -> lake build (annotated)
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

## How each contract is verified

For each contract the compiled validator is loaded once (via
`#import_blueprints`, straight from `../onchain/plutus.json`) and
every theorem runs `blaster` against that concrete program; the
datum/redeemer/value encodings mirror the on-chain types. Proofs are organized
in three directions plus the pure spec arithmetic:

- **Spec** (`Spec.lean`): the contract's arithmetic and relations, no UPLC.
- **Completeness** (`spec ⇒ accepts`, spec §8): honest actions are accepted.
- **Soundness** (`accepts ⇒ spec`, spec §9): acceptance forces a correct outcome.
- **Robustness** (rejection, spec §9): specific malformed or malicious actions
  are rejected.

Each contract documents its own coverage as a traceability table mapping
theorems to the spec clauses (invariants, the §8 C-clauses, the §9 R-clauses)
they discharge.

## Notes on `blaster` tractability

These apply to any contract:

- Prove against the **concrete** loaded validator. An abstract `validator :
  Program` parameter gives the SMT backend nothing to execute and hangs.
- Keep symbolic **structure** bounded. A fully symbolic `Value` (an arbitrary
  `Data` list) makes `quantity_of` run over an unbounded structure and does not
  terminate; shape values with builders and leave only Int/Datum leaves symbolic.
- Fully `∀`-quantified statements over an unconstrained `ScriptContext` generally
  do not terminate. Prove concrete instances; if a general statement is worth
  recording, keep it as a documented `sorry` target (we leave
  `warn.sorry` enabled so those surface as build warnings).

## Contracts

- **vesting/linear** — see [`Formal/Vesting/Linear/README.md`](Formal/Vesting/Linear/README.md)
  for its coverage tables and open targets.
