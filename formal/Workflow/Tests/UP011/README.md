# UP-011 workflow scenarios

The UP-011 scenarios check guarded continuation payment-credential rejection
through the native catalogue, app API, and engine. They use
[UP011/Definition.lean](../../../Formal/Properties/Universal/UP011/Definition.lean),
the original compiled fixture at [UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json),
and TxM-007 Claim. One registered combination produces a main obligation and
linked applicability, both using the 1,000,000 CEK-step bound.

Run the automated suites from `formal/`:

```sh
lake exe workflow_up011_tests
lake exe workflow_up011_tests --unit
lake exe workflow_up011_tests --negative-control
lake exe workflow_declarative_up011_tests
```

The automated scenario invokes the app API. The public CLI is a separate check:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-011 --timeout-ms 300000
```

The reference expectation is Valid for `continuationElsewhere_claim` and
`continuationElsewhere_claim_applies`, qualifying one PASS combination. These
expectations do not replace fresh execution evidence. The
[validation record](../../../Formal/Properties/Universal/UP011/VALIDATION.md)
records the checked commands and their limits.

The terminal's `Review` path links the `UP-011-v1-TxM-007` directory, containing
`check-result.json`, execution records, and generated `Types.lean`, `Tx.lean`,
and `Checks.lean`. Shared captured sources include the selected property and model
modules. Generated output stays under ignored `formal/output/` folders.

## Guards and applicability

The main goal retains five premises: baseline validity, bounded baseline
acceptance, bounded explicit rejection after redirection, a different payment
credential, and validity after the credential-only change. Applicability requires
a witness satisfying all five. A main observation cannot establish PASS without
trustworthy linked applicability.

Continuations match the spent input's payment credential alone. The tested
mutation changes only the first continuation's payment credential, preserving
its staking credential, value, and datum. The separate
`redirectContinuations` guard changes matching outputs' addresses and removes
their datums. Rejection of that combined change does not independently prove
address reliance. Rejection means an error or non-unit halt within 1,000,000 CEK
steps; fuel exhaustion does not count.

Cancel is not registered. TxM-008 supplies no continuation, making redirection
the identity and its acceptance/rejection premises incompatible. The older
generator emitted guarded checks for both action models without first proving
applicability. The preserved standalone Cancel applicability is an expected
falsification; its vacuous property result provides no mutation coverage.

## Admission and controls

The property admits only the original reference fixture. Its run declaration
skips the second vesting artifact recognized by native model admission. Native
admission rejects the incompatible vault. Both paths generate no proof
obligations and establish no passing property.

The negative control executes the frozen compiled
[address-ignoring program](../../../Formal/Properties/Universal/UP011/Tests/Standalone/Fixture.lean).
Its [Aiken source](../../../Formal/Properties/Universal/UP011/Tests/Standalone/Project/validators/ignore_address.ak)
requires an inline datum on the first output and ignores that output's address.
It accepts both the Claim baseline and its credential-only change, but rejects
redirection because redirection removes the datum. The control therefore retains
all five premises and expects a Falsified main goal with Valid applicability.
A timeout or compiler/solver error does not satisfy those expectations.

The control uses a distinct test identity and clears official property/binding
metadata. Its retained `input.json` contains the executed control blueprint;
`reference-input.json` contains the original vesting fixture and is marked as
reference-only. It is a real compiled control,
not a constant always-accepting substitute; the latter would fail the redirect
guard and could not establish applicability.

Separate synthetic observations check that missing, inconclusive, or falsified
applicability cannot qualify a main PASS. Those controls test assessment policy
without proving a validator property. `--unit` checks preparation and structure
without invoking the solver; the default suite includes app/engine execution and
retained results. `--negative-control` runs the compiled control separately.
The suites add no automatic Aiken build or duplicate validator fixture.

## Scope and earlier evidence

The [property guide](../../../Formal/Properties/Universal/UP011/README.md) records
all guards, the fixed model shape, original-artifact restriction, and Blaster
trust boundary. These checks establish neither the full address rule nor arbitrary
transaction coverage, ledger reachability, source correspondence, or funds safety.
A workflow timeout leaves the affected claim unresolved.

The [standalone guide](../../../Formal/Vesting/Linear/Blueprint/UP011.md) preserves
earlier results, direct commands, and the expected false Cancel applicability
diagnostic. Those observations remain historical. The
[workflow test index](../README.md) lists aggregate registration; neither suite
registration nor this guide claims a complete aggregate pass.
