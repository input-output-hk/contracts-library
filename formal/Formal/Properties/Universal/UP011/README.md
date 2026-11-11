# UP-011: guarded continuation payment-credential rejection

UP-011 checks rejection after changing the first continuation output's payment
credential in the fixed linear-vesting Claim model. The change preserves that
output's staking credential, value, and datum. Continuations match the spent
input's payment credential alone. This guarded claim does not
establish the full address rule or protection for arbitrary output positions.
[Definition.lean](Definition.lean) owns one primary statement and its supporting
applicability predicate; [metadata.json](metadata.json) records their scope.

The statement keeps all five premises from the standalone Claim formula:

1. **Baseline validity:** the original context satisfies `validScriptContext`.
2. **Baseline acceptance:** the validator accepts the original context within
   1,000,000 CEK steps.
3. **Redirect rejection:** the validator explicitly rejects `redirectContinuations`
   within the same bound. That helper changes every matching continuation's
   address to an attacker key address and removes its datum.
4. **Different credential:** the supplied payment credential differs from the
   first continuation's payment credential.
5. **Changed-context validity:** changing only that payment credential leaves
   the context model-valid.

Under those premises, the validator must explicitly reject the credential change
within 1,000,000 CEK steps. An error or non-unit halt counts as rejection; fuel
exhaustion does not. Applicability requires a witness satisfying all five
premises. The redirect guard tests a combined address-and-datum change, so its
rejection alone does not establish independent reliance on the address.

## Run the reference check

With the [workflow prerequisites](../../../../Workflow/Docs/USER-GUIDE.md#prepare-once)
available, run from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-011 --timeout-ms 300000
```

[Run.lean](Run.lean) registers only TxM-007 Claim. Its single combination emits
two linked obligations:

| Role | Obligation | Expected reference observation |
| --- | --- | --- |
| Primary | `continuationElsewhere_claim` | Valid |
| Applicability | `continuationElsewhere_claim_applies` | Valid |

These observations qualify one PASS combination, not two checks. A primary
observation cannot establish PASS without trustworthy linked applicability.
Missing, falsified, timed-out, or untrusted applicability leaves the property
unresolved. The command and expectations are not a record of a fresh run; consult
the [validation record](VALIDATION.md) and retained execution evidence.

Open the terminal's `Review` path. The
`validators/linear_vesting.linear_vesting/UP-011-v1-TxM-007/` directory retains
generated `Types.lean`, `Tx.lean`, and `Checks.lean`, plus result and execution
records. The shared source snapshot captures imported property and model modules.
A zero app exit records completed orchestration and retention, separately from
the proof outcome.

## Scope and admission

The run declaration admits only the original compiled artifact in
`Workflow/Tests/UP012/Inputs/plutus.json`. It skips the second vesting artifact
recognized by native TxM-007 admission. Unknown artifacts remain unsupported.
These paths produce no proof obligations and establish no passing property.
Default selection and the existing all-enabled example switch file include UP-011.

TxM-007 has two inputs and two outputs: a script continuation with an inline datum
first, then a payout. It uses one signer, one vested asset under fixed `policyA`,
key credentials for the beneficiary and locker, and addresses without staking
credentials. The model does not constrain its symbolic script credential to the
supplied program's hash. It excludes reference inputs, minting, and withdrawals. The mutation
preserves staking, value, and datum even though this model constructs addresses
without staking credentials.

Cancel is not a runnable UP-011 combination. TxM-008 has no continuation, so
redirection leaves its context unchanged. An accepted baseline cannot also meet
the redirect-rejection premise. The earlier generator emitted the same guarded
check for both action models; emission did not establish applicability. The
[standalone guide](../../../Vesting/Linear/Blueprint/UP011.md) retains the Cancel
property's vacuous Valid result and expected false applicability diagnostic.
Neither supplies Cancel mutation coverage.

Results retain the fixed model, artifact, 1,000,000-step allowance, and Blaster
SMT trust boundary. They do not establish full-address protection, arbitrary
transaction coverage, ledger reachability, source correspondence, or funds safety.
The CEK bound is separate from ledger execution budgets and the CLI wall-clock
timeout. A timeout or compiler/solver error leaves the affected claim unresolved.
Broader address protection remains open in
[issue #32](https://github.com/no-witness-labs/contracts-library/issues/32).

## Tests and provenance

Focused commands from `formal/`:

```sh
lake exe workflow_declarative_up011_tests
lake exe workflow_up011_tests
lake exe workflow_up011_tests --unit
lake exe workflow_up011_tests --negative-control
```

[Tests.lean](Tests.lean) checks the Claim-only binding, original-artifact
restriction, and equivalence to the preserved standalone formulas. The
[workflow scenario](../../../../Workflow/Tests/UP011/README.md) exercises the
native app API, retained output, skip paths, and linked applicability assessment.
The public CLI command above is a separate end-to-end check. Both suites are
registered in the aggregate; registration does not claim a complete aggregate pass.

The negative control executes the existing compiled
[address-ignoring validator](Tests/Standalone/Project/validators/ignore_address.ak).
It requires the first output's inline datum but ignores the address, so it accepts
both the baseline and the credential-only change. Redirection removes the datum
and still rejects, preserving the guard. The expected observations are Falsified
for the primary obligation and Valid for applicability. A constant always-accepting
program would fail that redirect guard and would not provide this control.

The standalone guide preserves the original formulas, attribution, dependency
pins, and measured results. Those historical observations do not establish a
fresh workflow run. Model authoring and further integration remain tracked in
issues #89 and #96.
