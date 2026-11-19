# Formal proofs

Lean specifications and proof targets for the contracts described under
[`docs/<contract>/spec.md`](../docs). The modules include pure model lemmas
and statements about imported compiled validators. A statement's hypotheses
and constructed context delimit its scope.

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
    ├── Shared/
    │   └── Common.lean      # shared `validatorAccepts` / `validatorRejects`
    ├── LinearVesting.lean   # imports both linear-vesting proof suites
    └── LinearVesting/
        ├── Spec.lean          # vesting arithmetic and datum encoding
        ├── Script.lean        # loads the compiled spending validator
        ├── Completeness.lean  # spec ⇒ accepts (§8)
        ├── Soundness.lean     # accepts ⇒ spec (§9) and shared context builders
        ├── Robustness.lean    # rejection theorems
        ├── SpecNew.lean       # specification for Claim and Cancel
        ├── Cancel.lean        # bounded agreement for Cancel
        ├── Claim.lean         # bounded agreement for Claim
        └── Corollaries.lean   # consequences of the agreement theorems
```

Each contract gets its own `Completeness`/`Soundness`/`Robustness` under its
folder, because the properties differ per contract. The layout follows
`francolq/aiken-good-practices` (`order-book/verify`). Contract READMEs map theorems
to the spec clauses they cover.

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
just verify      # build -> flats -> lake build (annotated)
```

For the manual sequence, put `just` and Aiken **v1.1.22** on `PATH`, alongside
Lean 4.24.0 and Z3 4.15.2 (provided by the dev shell).

```bash
cd formal
# (in `nix develop`, or with elan + z3 on PATH)
just flats       # compile Aiken and generate Scripts/*.flat
lake build       # type-check all modules and run every `blaster` proof
```

Lake uses the dependency revisions in `lake-manifest.json`. The `just deps`
recipe runs `lake update` when you intend to refresh those revisions.

Git ignores the generated files under `Scripts/`. `lake build` requires them;
run `just flats` before the first build and after changing the on-chain source.

A failing `blaster` goal can be debugged with its options, e.g.
`blaster (verbose: 1)` or `blaster (gen-cex: 1)` to print a counterexample.

## How each contract is verified

`Spec.lean` contains pure model lemmas. `Script.lean` loads the compiled
validator once via `#import_uplc`; the other proof modules use it with
constructed script contexts. The modules separate pure spec arithmetic
from completeness, soundness, and rejection targets:

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
- Fully quantified contexts can make direct symbolic execution intractable.
  A declaration containing `sorry` is an unfinished proof target. A passing
  build or a proof of a restricted instance does not discharge that target.

## Contracts

- The [linear-vesting README](Formal/LinearVesting/README.md) describes the
  catalogue, proof coverage, and bounds of the Claim and Cancel theorems.
