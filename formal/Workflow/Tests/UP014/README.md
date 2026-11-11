# UP-014 workflow scenarios

The UP-014 scenarios check guarded rejection of an empty-list continuation datum
through the native catalogue, app API, and engine. They use
[UP014/Definition.lean](../../../Formal/Properties/Universal/UP014/Definition.lean),
the original compiled fixture at [UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json),
and TxM-007 Claim. One registered combination produces a main obligation and
linked applicability, both using the 1,000,000 CEK-step bound.

Run the automated suites from `formal/`:

```sh
lake exe workflow_up014_tests
lake exe workflow_up014_tests --unit
lake exe workflow_up014_tests --negative-control
lake exe workflow_declarative_up014_tests
```

The automated scenario invokes the app API. The public CLI is a separate check:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-014 --timeout-ms 300000
```

The reference expectation is Valid for `continuationOtherDatum_claim` and
`continuationOtherDatum_claim_applies`, qualifying one PASS combination. These
expectations do not replace fresh execution evidence. The
[validation record](../../../Formal/Properties/Universal/UP014/VALIDATION.md)
records the checked commands and their limits.

The terminal's `Review` path links the `UP-014-v1-TxM-007` directory, containing
`check-result.json`, execution records, and generated `Types.lean`, `Tx.lean`,
and `Checks.lean`. Shared captured sources include the selected property and model
modules. Generated output stays under ignored `formal/output/` folders.

## Guards and applicability

The mutation replaces the first continuation's inline datum with exactly
`Constr 0 [credential1, credential2, List [], Int start, Int end, Int recovery]`.
The two credentials and three integers are symbolic, but the vesting-asset list
is always empty. The baseline datum contains one vested asset. Address and value
remain unchanged; this check does not cover nonempty replacement lists or general
datum integrity.

The main goal retains five premises: baseline validity, bounded baseline
acceptance, bounded explicit rejection after redirection, a different replacement
datum, and validity after the datum replacement. Applicability requires a witness
satisfying all five. A main observation cannot establish PASS without trustworthy
linked applicability.

Continuations match the spent input's payment credential alone. The separate
`redirectContinuations` guard changes matching outputs' addresses and removes
their datums. Rejection of that combined change does not independently prove
datum reliance. Rejection means an error or non-unit halt within 1,000,000 CEK
steps; fuel exhaustion does not count.

Cancel is not registered. TxM-008 supplies no continuation, making redirection
the identity and its acceptance/rejection premises incompatible. The preserved
standalone Cancel applicability is an expected falsification; its vacuous
property result provides no mutation coverage.

## Admission and controls

The property admits only the original reference fixture. Its run declaration
skips the second vesting artifact recognized by native model admission. Native
admission rejects the incompatible vault. Both paths generate no proof
obligations and establish no passing property.

The negative control executes the frozen compiled
[continuation gate](../../../Formal/Properties/Universal/UP014/Tests/Standalone/Inputs/control.json).
Its [Aiken source](../../../Formal/Properties/Universal/UP014/Tests/Standalone/Project/validators/continuation_gate.ak)
finds its own input, requires a script payment credential, and requires the first
output to keep that credential. It ignores the datum, accepting both the Claim
baseline and the empty-list replacement while rejecting redirection. All five
premises therefore remain satisfiable. The required observations are Falsified
for the main goal and Valid for applicability; a timeout or compiler/solver error
does not satisfy those expectations.

The control uses a distinct test identity and clears official property/binding
metadata. Its retained `input.json` contains the executed control blueprint and
its actual script hash; `reference-input.json` contains the original vesting
fixture and is marked as reference-only. A constant always-accepting program
would fail the redirect guard and could not establish applicability.

Separate synthetic observations check that missing, inconclusive, or falsified
applicability cannot qualify a main PASS. Those controls test assessment policy
without proving a validator property. `--unit` checks preparation and structure
without invoking the solver; the default suite includes app/engine execution and
retained results. `--negative-control` runs the compiled control separately.
The suites add no automatic Aiken build or duplicate validator fixture.

## Scope and earlier evidence

The [property guide](../../../Formal/Properties/Universal/UP014/README.md) records
all guards, the fixed model shape, original-artifact restriction, and Blaster
trust boundary. These checks establish neither broader datum integrity nor
arbitrary transaction coverage, ledger reachability, source correspondence, or
funds safety. A workflow timeout leaves the affected claim unresolved.

The [standalone guide](../../../Formal/Vesting/Linear/Blueprint/UP014.md) preserves
earlier results, direct commands, and the expected false Cancel applicability
diagnostic. Those observations remain historical. The
[workflow test index](../README.md) lists aggregate registration; neither suite
registration nor this guide claims a complete aggregate pass.
