# UP-001 standalone checks

These Lean files exercise the original UP-001 candidate without running a Python
generator or the workflow app. They preserve PR #49's **1,000,000 CEK-step**
nonacceptance statements for minting, withdrawal, certification, voting, and
proposing. The selected validator declares only spending; the `else` entry is
its fallback, not a sixth declared purpose.

## Fixed validator and scope

[Fixture.lean](Fixture.lean) embeds the 1404-byte compiled program from
`onchain/plutus.json`, entry `linear_vesting.linear_vesting.spend`, at candidate
commit `b44b6b0757a75d79b79a4de4712523ee3978760e`. The blueprint records Aiken
`v1.1.22+39d6b04`, Plutus V3, Apache-2.0 licensing, and script hash
`95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a`.
The fixture compares the recorded hash and exact code with the tracked blueprint;
it does not independently recompute the hash.

This validator has no unapplied parameters. These results provide no evidence
for the legacy generator's quantified-parameter path. Every raw redeemer and
every field of the shared `Every*` context models remain symbolic. No ledger-
validity premise restricts those contexts.

Fuel exhaustion satisfies the claim. A passing result therefore establishes no
unit-valued acceptance within the stated CEK allowance; it does not establish
explicit rejection, termination, ledger CPU/memory compliance, or general safety.
Blaster's `blasterProven` trust remains; it supplies no reconstructed proof term.

## Run

Use the committed Lean and dependency revisions with Z3 available. From `formal/`:

```sh
lake build Formal.Universal.Properties
mkdir -p .lake/build/lib/lean/tests/UP001
lake env lean -o .lake/build/lib/lean/tests/UP001/Fixture.olean tests/UP001/Fixture.lean
timeout --kill-after=5s 300s lake env lean -j4 --json tests/UP001/Checks.lean
```

Expected: the source-artifact check succeeds, all five obligations report `Valid`,
and Lean exits zero. The file also prints each successful theorem's axioms.
Any timeout or compiler error leaves validation incomplete. The deadline limits
wall-clock execution; it does not change the claim's 1,000,000-step bound.

Then run the deliberately false control separately:

```sh
timeout --kill-after=5s 300s lake env lean -j4 --json tests/UP001/AcceptingControl.lean
```

Expected: all five obligations report `Falsified`, and Lean exits nonzero because
these theorem statements are intentionally false. A nonzero exit alone is not a
passing control: syntax/import errors and timeouts do not demonstrate falsification.
The control uses a synthetic UPLC program that ignores the context and returns
unit. It is not a compiled Aiken fixture or a claim about a deployed validator.

## Relationship to the generator

[Checks.lean](Checks.lean) retains the unparameterized statements produced by
`other_purpose_checks` in `scripts/process_blueprint.py`: the same quantifiers,
`Every*` context families, `ledgerFuel`, and negated acceptance predicate. It
supplies a fixed program directly instead of importing generated `Types.lean`.
The source check rejects changes to the tracked program, its declared purposes,
Plutus version, or parameter status, so a changed blueprint cannot silently reuse
the old artifact under the same fixture label.

The existing Python tests cover generator/source behavior. These standalone files
provide separate executable proof and falsification controls. They do not claim
that every translated blueprint or parameter encoding is correct. The active
workflow's separately approved 5,000,000-step configuration is outside this
candidate's original standalone scope.

Standalone validation on 2026-11-02 passed the source-artifact check and produced
five Valid observations in 81.083 seconds, exit 0. The synthetic accepting control
produced five Falsified observations with counterexamples in 45.613 seconds,
expected exit 1. All five theorem axiom listings contain standard Lean axioms and
`blasterProven`, without `sorryAx`.

App integration and reconciliation with native model/definition registration are
checkpoint-2 work under [issue #96](https://github.com/no-witness-labs/contracts-library/issues/96).
Broader claim and coverage review remains open in
[issue #23](https://github.com/no-witness-labs/contracts-library/issues/23).
