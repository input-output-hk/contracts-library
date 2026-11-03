# Formal verification

This Lake project contains the Plutus UPV app, reusable property and transaction
model banks, and contract-specific specification proofs.

For Plutus UPV (Universal Property Verifier), use the
[CLI quickstart](Workflow/Docs/USER-GUIDE.md). The app uses Lean for property discovery,
model preparation, and verification with the installed Lean/Z3 tools.
From `formal/`, `./plutus-upv test` runs all workflow tests with verbose
logs; `./plutus-upv run ...` verifies properties of a supplied compiled validator.
The guide includes passing, failing, and inconclusive examples.

Proofs are written in [Lean 4](https://lean-lang.org/) and discharged with
[Lean-Blaster](https://github.com/input-output-hk/Lean-blaster), an SMT (Z3)
backend invoked via the `blaster` tactic.

## Layout

```text
formal/
├── plutus-upv / install.sh  # public command and checkout-backed installation
├── lakefile.toml           # libraries, executable targets, and dependencies
├── lean-toolchain          # pinned Lean version
├── Formal/
│   ├── Properties/         # property definitions, run instructions, metadata, tests
│   ├── TxModels/           # reusable transaction models and their metadata
│   ├── Universal/          # evaluator/ledger theory and shared helpers
│   ├── Vesting/            # specification proofs and standalone checkpoints
│   ├── Vault/              # standalone hashed-datum checkpoint
│   └── Settings/           # standalone minting checkpoint
├── Workflow/
│   ├── App/                # current CLI and orchestration
│   ├── Input/, Generator/, Executor/, Assessor/
│   └── Tests/Legacy/       # older providers, reports, and internal fixture driver
├── Universal/              # earlier harness/demo prototype
├── tests/                  # standalone candidate and translator tests/fixtures
├── docs/                   # foundation and standalone-check documentation
└── scripts/                # shared translation and proof utility scripts
```

Each contract gets its own `Completeness`/`Soundness`/`Robustness` under its
folder, because the properties differ per contract. The layout follows
`francolq/aiken-good-practices` (`order-book/verify`). Every theorem carries a
doc comment citing the spec section it discharges (e.g. `§9 B1`).

## Specification-proof tooling

For the contract-specific proof pipeline below, the existing optional Nix
environment supplies its tools. The Plutus UPV command uses the prepared
Lean/Z3 environment described in its [user guide](Workflow/Docs/USER-GUIDE.md).

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

## Specification-proof pipeline

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
lake build       # build the Formal specification-proof target
```

A failing `blaster` goal can be debugged with its options, e.g.
`blaster (verbose: 1)` or `blaster (gen-cex: 1)` to print a counterexample.

## Contract specification proofs

These proofs accompany `onchain/`, `offchain/`, and the contract specifications
under `docs/<contract>/spec.md`. See [the architecture](../docs/ARCHITECTURE.md) §2.

## How each contract is verified

For each contract the compiled validator is loaded once (via `#import_uplc`) and
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

- **vesting/linear**: see [`Formal/Vesting/Linear/README.md`](Formal/Vesting/Linear/README.md)
  for its coverage tables and open targets.

## Candidate checks

See [UP-002 preparation, bounds, and standalone proof jobs](docs/UP002.md).
The files below define the historical propositions; `lake build Universal`
typechecks their models without running the separate solver jobs.

| Candidate | Validator/action | Lean file |
| --- | --- | --- |
| UP-002 | Linear vesting / Claim | [NoSignatureClaim.lean](Universal/Demo/Linear_vesting/NoSignatureClaim.lean) |
| UP-002 | Linear vesting / Cancel | [NoSignatureCancel.lean](Universal/Demo/Linear_vesting/NoSignatureCancel.lean) |
| UP-002 | Vault / Spend | [NoSignatureSpend.lean](Universal/Demo/Vault/NoSignatureSpend.lean) |
| UP-002 | Buggy vault / Spend (negative example) | [NoSignatureSpend.lean](Universal/Demo/Vault_buggy/NoSignatureSpend.lean) |
