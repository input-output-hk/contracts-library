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

Use Lean 4.24.0, Z3 4.15.2, and the dependency revisions pinned by
`lake-manifest.json`. From `formal/`:

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

The reconciled legacy generator contains UP001, UP005, and UP006; its retained
regression run passed 47 Python tests. Those tests cover generator/source behavior.
These standalone files provide separate executable proof and falsification
controls, without invoking Python. They do not establish correctness for every
translated blueprint or parameter encoding. The active workflow's separately
approved 5,000,000-step configuration is outside this candidate's original
standalone scope; its typed/unapplied parameter support remains separate work.

## Retained evidence

Standalone validation on 2026-11-02 passed the source-artifact check and produced
five Valid observations in 81.083 seconds, exit 0. The synthetic accepting control
produced five Falsified observations with counterexamples in 45.613 seconds,
expected exit 1. All five theorem axiom listings contain standard Lean axioms and
`blasterProven`, without `sorryAx`.

The local delivery manifest records the tested commit, source and log hashes,
artifact identity, dependency pins, commands, and observed results. The three
Lean files, shared context definitions, blueprint, and dependency/configuration
files are byte-identical to the standalone checkpoint at
`b573deba8d55fcda7cdeafd5b78c3c27857e2130`. Later legacy-generator reconciliation
changed three separate generator, regression-test, and guide files. The retained
results therefore apply to the unchanged standalone inputs; they are not a new
solver run on the final combined source tree.

The raw logs and receipts remain local under
`formal/.lake/workflow-review/candidate-checkpoint-1/`, with the manifest at
`delivery/UP001-evidence.json` beneath that directory. The fixture's source check
compares the recorded script hash, while a separate source review recomputed the
V3 hash from the compiled bytes.

UP001 has no accepted-baseline premise or applicability implication to discharge.
Its relevance depends on the declared handlers representing the validator's
intended purposes. Declaring every purpose produces no UP001 obligations; it is
not evidence of a passing property check.

App integration and reconciliation with native model/definition registration are
checkpoint-2 work under [issue #96](https://github.com/no-witness-labs/contracts-library/issues/96).
Broader claim and coverage review remains open in
[issue #23](https://github.com/no-witness-labs/contracts-library/issues/23).
