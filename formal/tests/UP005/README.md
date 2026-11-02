# UP-005 standalone checks

These Lean files preserve the eight selected malformed-redeemer checks from
[PR #50](https://github.com/no-witness-labs/contracts-library/pull/50) for one
fixed linear-vesting validator. The original checks and shared context helpers
come from sayyadirfanali's [PR #44](https://github.com/no-witness-labs/contracts-library/pull/44),
revision `99a5734f0e036b6abfb4c3f121a298e35fa2eff6`. They address part of
[issue #26](https://github.com/no-witness-labs/contracts-library/issues/26).

## Fixed validator and claim

[Fixture.lean](Fixture.lean) embeds the 1404-byte compiled program from
`onchain/plutus.json`, entry `linear_vesting.linear_vesting.spend`, at candidate
revision `0368e24b95aadc51d2ec7a9a435cc1da769888c9`. The blueprint records Aiken
`v1.1.22+39d6b04`, Plutus V3, Apache-2.0 licensing, and script hash
`95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a`.
The fixture compares the recorded hash and exact code with the tracked blueprint;
it does not independently recompute the hash. It also decodes the tracked bytes
and compares that program with the embedded proof program.

The validator declares spending and an `else` fallback. Its typed spending
redeemer has `Claim` at constructor index 0 and `Cancel` at index 1, both with no
fields. The fallback has an untyped schema and produces no UP-005 obligation.
The source check requires those exact handler declarations, redeemer schemas,
and referenced redeemer definition. A primitive, missing, or changed schema fails
the fixture precondition; these files do not infer replacement cases.

Each theorem asserts **no unit-valued acceptance within 1,000,000 CEK steps**.
All `EverySpend` fields remain symbolic: the complete `TxInfo`, spending
reference, and optional raw datum. No ledger-validity premise restricts those contexts.
Fuel exhaustion satisfies the claim, so `Valid` does not establish explicit
rejection, termination, ledger CPU/memory compliance, or general validator safety.

| Selected malformed redeemer | Quantified values | Obligations |
| --- | --- | --- |
| Integer, bytes, list, or map instead of a constructor | Any value of each form | 4 |
| Constructor 2 or 3, neither declared by this blueprint | Any list of raw fields | 2 |
| Claim or Cancel with exactly one extra field | Any raw `Data` field | 2 |

Coverage is partial. Only indices 2 and 3 represent unknown constructors. Other
unknown indices and more than one extra field on a known constructor are not
checked. Missing-field and wrong-field-kind cases do not apply to these two
zero-field constructors. This validator has no unapplied parameters. These checks
do not validate the legacy generator's quantified-parameter path.

## Run

Use Lean `v4.24.0` from `lean-toolchain` and Z3 `4.15.2` on `PATH`. Retain the
committed `lake-manifest.json` revisions:

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | `577e3eb03b5be09354cfdb1c0d0c12e9e16541a0` |
| PlutusCore | `4ef48606303c45225d3ed2e2a87fc50280a763b7` |
| Blaster | `402f6d22c1fc42e6e26255faac77e15b2450e4ab` |

From `formal/`, build the shared helpers and freshly compile the embedded fixture
before running the checks. The package config uses four Lean workers; the direct
Lean invocations below also specify four workers.

```sh
timeout --kill-after=5s 300s lake build Formal.Universal.Properties
mkdir -p .lake/build/lib/lean/tests/UP005
timeout --kill-after=5s 300s lake env lean -j4 -o .lake/build/lib/lean/tests/UP005/Fixture.olean tests/UP005/Fixture.lean
timeout --kill-after=5s 300s lake env lean -j4 --json tests/UP005/Checks.lean
```

Expected: the source-artifact check succeeds, all eight obligations report
`Valid`, and Lean exits zero. The file prints each theorem's axioms. Blaster's
`blasterProven` trust remains; it supplies no reconstructed proof term. A timeout,
source mismatch, or compiler error leaves validation incomplete. The 300-second
deadlines limit wall-clock execution and do not change the CEK-step bound.

Run the deliberately false control separately:

```sh
timeout --kill-after=5s 300s lake env lean -j4 --json tests/UP005/AcceptingControl.lean
```

Expected: all eight obligations report `Falsified`, with counterexamples, and
Lean exits nonzero. A nonzero exit alone is insufficient: import errors, syntax
errors, and timeouts do not establish falsification. The synthetic UPLC control
ignores the context and returns unit. It retains the same eight formulas and
1,000,000-step allowance. It is not an Aiken or deployed validator.

## Relationship to the candidate

[Checks.lean](Checks.lean) manually retains the unparameterized statements from
`malformed_redeemer_checks` in `scripts/process_blueprint.py`: the quantifiers,
`EverySpend` contexts, malformed terms, `ledgerFuel`, and negated acceptance are
unchanged. The known constructor indices come from the pinned blueprint, whose
schema the fixture checks. The standalone commands do not run a Python generator
or the workflow app. The existing generator and its tests remain unchanged.

Checkpoint 2 covers:

- App integration and native definition/model registration in [issue #96](https://github.com/no-witness-labs/contracts-library/issues/96).
- Broader models in [issue #89](https://github.com/no-witness-labs/contracts-library/issues/89).
- Parameters in [issue #88](https://github.com/no-witness-labs/contracts-library/issues/88).

The differences from issue #26's ledger-validity and explicit-rejection wording,
and broader malformed-form coverage, remain open under
[issue #26](https://github.com/no-witness-labs/contracts-library/issues/26).

## Recorded validation

Standalone validation on 2026-11-02 used the commands above with JSON diagnostics.
The source-artifact/schema check passed. Eight original-scope obligations returned Valid in 75.413 seconds, exit 0. The accepting control produced eight Falsified observations with counterexamples in 63.432 seconds, expected exit 1. All eight original theorem axiom listings exclude sorryAx.
Standard Lean axioms and Blaster's SMT trust remain. These are scoped candidate
results; app integration is not part of this checkpoint.
