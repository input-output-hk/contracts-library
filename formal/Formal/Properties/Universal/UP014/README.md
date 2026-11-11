# UP-014: guarded empty-list continuation-datum rejection

UP-014 checks rejection after replacing the first continuation's inline datum
in the fixed linear-vesting Claim model. The replacement has exactly this shape:

```text
Constr 0 [credential1, credential2, List [], Int start, Int end, Int recovery]
```

The two credentials and three integers are symbolic. The vesting-asset list is
always empty; the baseline Claim datum contains one vested asset. The mutation
preserves the output's address and value. It adds no semantic validity constraint
on the replacement credentials or schedule. It does not cover every typed
`VestingDatum`, nonempty replacement lists, or broader datum integrity.
[Definition.lean](Definition.lean) owns one primary statement and its supporting
applicability predicate; [metadata.json](metadata.json) records their scope.

The statement keeps all five premises from the standalone Claim formula:

1. **Baseline validity:** the original context satisfies `validScriptContext`.
2. **Baseline acceptance:** the validator accepts the original context within
   1,000,000 CEK steps.
3. **Redirect rejection:** the validator explicitly rejects `redirectContinuations`
   within the same bound. That helper changes every matching continuation's
   address to an attacker key address and removes its datum.
4. **Different datum:** the first continuation's inline datum differs from the
   supplied replacement.
5. **Changed-context validity:** replacing only that datum leaves the context
   model-valid.

Under those premises, the validator must explicitly reject the datum replacement
within 1,000,000 CEK steps. An error or non-unit halt counts as rejection; fuel
exhaustion does not. Applicability requires a witness satisfying all five
premises. Continuations match the spent input's payment credential alone.
The redirect guard changes both address and datum, so its rejection does not
independently establish reliance on the datum.

## Run the reference check

With the [workflow prerequisites](../../../../Workflow/Docs/USER-GUIDE.md#prepare-once)
available, run from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-014 --timeout-ms 300000
```

[Run.lean](Run.lean) registers only TxM-007 Claim. Its single combination emits
two linked obligations:

| Role | Obligation | Expected reference observation |
| --- | --- | --- |
| Primary | `continuationOtherDatum_claim` | Valid |
| Applicability | `continuationOtherDatum_claim_applies` | Valid |

These observations qualify one PASS combination. A primary observation cannot
establish PASS without trustworthy linked applicability. Missing, falsified,
timed-out, or untrusted applicability leaves the property unresolved. The command
and expectations are not a record of a fresh run; consult the
[validation record](VALIDATION.md) and retained execution evidence.

Open the terminal's `Review` path. The
`validators/linear_vesting.linear_vesting/UP-014-v1-TxM-007/` directory retains
generated `Types.lean`, `Tx.lean`, and `Checks.lean`, plus result and execution
records. The shared source snapshot captures imported property and model modules.
A zero app exit records completed orchestration and retention, separately from
the proof outcome.

## Scope and admission

The run declaration admits only the original compiled artifact in
`Workflow/Tests/UP012/Inputs/plutus.json`. It skips the second vesting artifact
recognized by native TxM-007 admission. Unknown artifacts remain unsupported.
These paths produce no proof obligations and establish no passing property.
Default selection and the existing all-enabled example switch file include UP-014.

TxM-007 has two inputs and two outputs: a script continuation with an inline datum
first, then a payout. It uses one signer, one vested asset under fixed `policyA`,
key credentials for the beneficiary and locker, and addresses without staking
credentials. The model does not constrain its symbolic script credential to the
supplied program's hash. It excludes reference inputs, minting, and withdrawals.
The changed datum falls outside this baseline family, so its validity remains
an explicit premise.

Cancel is not a runnable UP-014 combination. TxM-008 has no continuation, so
redirection leaves its context unchanged. An accepted baseline cannot also meet
the redirect-rejection premise. The
[standalone guide](../../../Vesting/Linear/Blueprint/UP014.md) retains the Cancel
property's vacuous Valid result and expected false applicability diagnostic.
Neither supplies Cancel mutation coverage.

Results retain the fixed model, artifact, 1,000,000-step allowance, and Blaster
SMT trust boundary. They do not establish general datum integrity, arbitrary
transaction coverage, ledger reachability, source correspondence, or funds safety.
The CEK bound is separate from ledger execution budgets and the CLI wall-clock
timeout. A timeout or compiler/solver error leaves the affected claim unresolved.
Broader datum replacement and the intended general rule remain open in
[issue #35](https://github.com/no-witness-labs/contracts-library/issues/35).

## Tests and provenance

Focused commands from `formal/`:

```sh
lake exe workflow_declarative_up014_tests
lake exe workflow_up014_tests
lake exe workflow_up014_tests --unit
lake exe workflow_up014_tests --negative-control
```

[Tests.lean](Tests.lean) checks the Claim-only binding, original-artifact
restriction, and equivalence to the preserved standalone formulas. The
[workflow scenario](../../../../Workflow/Tests/UP014/README.md) exercises the
native app API, retained output, skip paths, and linked applicability assessment.
The public CLI command above is a separate end-to-end check. Both suites are
registered in the aggregate; registration does not claim a complete aggregate pass.

The negative control executes the existing compiled
[continuation gate](Tests/Standalone/Project/validators/continuation_gate.ak).
It finds its own input and requires the first output to keep that input's script
payment credential, while ignoring the datum. It accepts the baseline and datum
replacement but rejects redirection, retaining all five premises. The required
observations are Falsified for the primary obligation and Valid for applicability.
A constant always-accepting program would fail the redirect guard and could not
provide this control. The control retains its actual compiled input and script
hash under a distinct test identity, with official property/binding metadata cleared.

The standalone guide preserves the original formulas, attribution, dependency
pins, and measured results. Those historical observations do not establish a
fresh workflow run. Model authoring and further integration remain tracked in
issues #89 and #96.
