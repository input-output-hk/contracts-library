# UP-007 workflow scenarios

The UP-007 scenarios preserve an expected official FAIL for guarded continuation
staking-credential rejection on the original linear-vesting artifact. They use
[UP007/Definition.lean](../../../Formal/Properties/Universal/UP007/Definition.lean),
the original compiled fixture at [UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json),
and TxM-007 Claim through the native catalogue, app API, and engine. One registered
combination produces a main obligation and linked applicability, both using the
1,000,000 CEK-step bound.

Run the automated suites from `formal/`:

```sh
lake exe workflow_up007_tests
lake exe workflow_up007_tests --unit
lake exe workflow_up007_tests --control
lake exe workflow_declarative_up007_tests
```

The automated scenario invokes the app API. The public CLI is a separate check:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-007 --timeout-ms 300000
```

The reference expectation is Falsified for `continuationStake_claim` and Valid
for `continuationStake_claim_applies`, producing one official FAIL combination.
The native main goal still expects Valid; the regression test requires the
reference's actual Falsified observation and resulting FAIL. A passing regression
suite therefore does not mean the reference property passes. These expectations
do not replace fresh execution evidence. The
[validation record](../../../Formal/Properties/Universal/UP007/VALIDATION.md)
records the checked commands and their limits.

The terminal's `Review` path links the `UP-007-v1-TxM-007` directory, containing
`check-result.json`, execution records, and generated `Types.lean`, `Tx.lean`,
and `Checks.lean`. Shared captured sources include the selected property and model
modules. Generated output stays under ignored `formal/output/` folders.
A zero app exit means orchestration and retention completed; the individual
property remains FAIL when its qualified observations falsify the rule.

## Guards and applicability

The main goal retains five premises: baseline validity, bounded baseline
acceptance, bounded explicit rejection after redirection, a different optional
staking credential, and validity after the staking-only change. Applicability
requires a witness satisfying all five. A main observation cannot qualify a
guarded verdict without trustworthy linked applicability.

Continuations match the spent input's payment credential alone. The mutation
changes only the first continuation's staking credential, preserving its payment
credential, value, and datum. The original own input and continuation have no
staking credential. The separate `redirectContinuations` guard changes matching
outputs' addresses and removes their datums. Rejection of that combined change
does not independently prove reliance on staking credentials. Rejection means an
error or non-unit halt within 1,000,000 CEK steps; fuel exhaustion does not count.

Cancel is not registered. TxM-008 supplies no continuation, making redirection
the identity and its acceptance/rejection premises incompatible. The preserved
standalone Cancel applicability is an expected falsification; its vacuous primary
result provides no mutation coverage.

## Admission and control

The property admits only the original reference fixture. Its run declaration
skips the second vesting artifact recognized by native model admission. Native
admission rejects the incompatible vault. Both paths generate no proof
obligations and establish no passing property.

The enforcing control executes the frozen compiled
[stake-enforcing program](../../../Formal/Properties/Universal/UP007/Tests/Standalone/Control.lean).
Its [Aiken source](../../../Formal/Properties/Universal/UP007/Tests/Standalone/Project/validators/stake_control.ak)
finds its own input and requires the first output to keep both that input's
payment and staking credentials. The control preserves the model, all five
premises, and the bound. It expects Valid main and applicability observations,
producing a test-only PASS. A timeout or compiler/solver error does not satisfy
those expectations.

The control uses a distinct test identity and clears official property/binding
metadata. Its retained `input.json` contains the executed control blueprint;
`reference-input.json` contains the original vesting fixture and is marked as
reference-only. `control-result.json` records the assessment and executed program
hash; `execution.json` links the observations, generated sources, and logs.
The [control implementation](PassingControl.lean) adds no official property/model binding and no automatic
Aiken build. The original reference's applicable falsification supplies the
counterpart to this enforcing control.

Separate synthetic observations check that missing, inconclusive, or falsified
applicability leaves either a Valid or Falsified main observation unresolved.
Those controls test assessment policy without proving a validator property.
`--unit` checks preparation and structure
without invoking the solver; the default suite includes app/engine execution,
the enforcing control, and retained results.
Use `--control` to run only the compiled enforcing control.

## Scope and earlier evidence

The [property guide](../../../Formal/Properties/Universal/UP007/README.md) records
the fixed model, symbolic script credential, original-artifact restriction, and
Blaster trust boundary. Falsification refutes this guarded first-continuation
rejection rule. It establishes neither a vulnerability nor full staking-credential
preservation, arbitrary transaction coverage, ledger reachability, or funds loss.
A workflow timeout leaves the affected claim unresolved.

The [standalone guide](../../../docs/UP007.md) preserves earlier results, direct
commands, and the expected false Cancel applicability diagnostic. Those
observations remain historical. The [workflow test index](../README.md) lists
aggregate registration; neither suite registration nor this guide claims a
complete aggregate pass.
