# UP-007: guarded continuation staking-credential rejection

UP-007 checks rejection after changing only the first continuation output's
staking credential in the fixed linear-vesting Claim model. The original reference
artifact is expected to falsify this guarded rejection rule, with Valid linked
applicability, producing one official FAIL combination. This expectation preserves
the standalone result; it does not establish a vulnerability or a general
staking-credential preservation requirement.

[Definition.lean](Definition.lean) owns one primary statement and its supporting
applicability predicate; [metadata.json](metadata.json) records their scope.
The statement keeps all five premises from the standalone Claim formula:

1. **Baseline validity:** the original context satisfies `validScriptContext`.
2. **Baseline acceptance:** the validator accepts the original context within
   1,000,000 CEK steps.
3. **Redirect rejection:** the validator explicitly rejects `redirectContinuations`
   within the same bound. That helper changes every matching continuation's
   address to an attacker key address and removes its datum.
4. **Different staking credential:** the supplied optional staking credential
   differs from the first continuation's staking credential.
5. **Changed-context validity:** changing only that staking credential leaves
   the context model-valid.

Under those premises, the validator must explicitly reject the staking-credential
change within 1,000,000 CEK steps. An error or non-unit halt counts as rejection;
fuel exhaustion does not. Applicability requires a witness satisfying all five
premises. Continuations match the spent input's payment credential alone.
The redirect guard changes both address and datum, so its rejection does not
independently establish reliance on staking credentials.

## Run the reference check

With the [workflow prerequisites](../../../../Workflow/Docs/USER-GUIDE.md#prepare-once)
available, run from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-007 --timeout-ms 300000
```

[Run.lean](Run.lean) registers only TxM-007 Claim. Its single combination emits
two linked obligations:

| Role | Obligation | Expected reference observation | Native goal expectation |
| --- | --- | --- | --- |
| Primary | `continuationStake_claim` | Falsified | Valid |
| Applicability | `continuationStake_claim_applies` | Valid | Valid |

The native primary expectation stays Valid. The reference's expected Falsified
observation therefore produces FAIL; the regression test expects that official
failure. Valid applicability establishes that the five premises have a witness.
Missing, falsified, timed-out, or untrusted applicability leaves the guarded claim
unresolved. These expectations are not a record of a fresh run; consult the
[validation record](VALIDATION.md) and retained execution evidence.

Open the terminal's `Review` path. The
`validators/linear_vesting.linear_vesting/UP-007-v1-TxM-007/` directory retains
generated `Types.lean`, `Tx.lean`, and `Checks.lean`, plus result and execution
records. The shared source snapshot captures imported property and model modules.
A zero app exit records completed orchestration and retention, separately from
the FAIL property outcome.

## Scope and admission

The run declaration admits only the original compiled artifact in
`Workflow/Tests/UP012/Inputs/plutus.json`. It skips the second vesting artifact
recognized by native TxM-007 admission. Unknown artifacts remain unsupported.
These paths produce no proof obligations and establish no passing property.
Default selection and the existing all-enabled example switch file include UP-007.

TxM-007 has two inputs and two outputs: a script continuation with an inline datum
first, then a payout. It uses one signer, one vested asset under fixed `policyA`,
and key credentials for the beneficiary and locker. The original own input and
continuation have no staking credential. The mutation preserves the continuation's
payment credential, value, and datum. The model does not constrain its symbolic
script credential to the supplied program's hash. It excludes reference inputs,
minting, and withdrawals. The check does not cover arbitrary output order or
multiple continuations.

Cancel is not a runnable UP-007 combination. TxM-008 has no continuation, so
redirection leaves its context unchanged. An accepted baseline cannot also meet
the redirect-rejection premise. The [standalone guide](../../../../docs/UP007.md)
retains Cancel's vacuous Valid primary result and expected Falsified applicability.
Neither supplies Cancel mutation coverage.

Results retain the fixed model, artifact, 1,000,000-step allowance, and Blaster
SMT trust boundary. A falsification refutes this guarded, bounded first-continuation
rejection rule. It does not establish acceptance of every staking change, a
vulnerability, ledger reachability, source correspondence, or funds loss.
The full input/output staking-credential preservation rule remains open in
[issue #28](https://github.com/no-witness-labs/contracts-library/issues/28).
The CEK bound is separate from ledger execution budgets and the CLI wall-clock
timeout. A timeout or compiler/solver error leaves the affected claim unresolved.

## Tests and provenance

Focused commands from `formal/`:

```sh
lake exe workflow_declarative_up007_tests
lake exe workflow_up007_tests
lake exe workflow_up007_tests --unit
lake exe workflow_up007_tests --control
```

[Tests.lean](Tests.lean) checks the Claim-only binding, original-artifact
restriction, and equivalence to the preserved standalone formulas. The
[workflow scenario](../../../../Workflow/Tests/UP007/README.md) exercises the
native app API, retained output, skip paths, and linked applicability assessment.
The public CLI command above is a separate end-to-end check. Both suites are
registered in the aggregate; registration does not claim a complete aggregate pass.

The compiled [stake-enforcing control](Tests/Standalone/Control.lean) finds its own
input and requires the first output to preserve both its payment and staking
credentials. It retains the model, all five premises, and the CEK bound. Its
expected primary and applicability observations are both Valid, producing a
test-only PASS. The control retains its actual compiled input and script hash
under a distinct test identity, with official property/binding metadata cleared.
It does not add another official UP-007 combination.
Use `--control` to run this compiled control separately.

The standalone guide preserves the original formulas, attribution, dependency
pins, and measured results. Those historical observations do not establish a
fresh workflow run. Model authoring and further integration remain tracked in
issues #89 and #96.
