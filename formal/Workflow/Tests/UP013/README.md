# UP-013 workflow scenarios

The UP-013 scenarios exercise fully unbounded-range rejection through the native
catalogue, app API, and engine. They use
[UP013/Definition.lean](../../../Formal/Properties/Universal/UP013/Definition.lean),
the original compiled vesting fixture at
[UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json), TxM-007 Claim, and TxM-008
Cancel. Acceptance and explicit rejection retain the 1,000,000 CEK-step bound.

From `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-013 --timeout-ms 300000
lake exe workflow_up013_tests
lake exe workflow_up013_tests --unit
lake exe workflow_declarative_up013_tests
```

Each combination generates a main rejection obligation and a linked applicability
obligation. The baseline must satisfy `validScriptContext` and the validator must
accept it within the bound. Replacing only its validity range with `rangeAlways`
produces the changed context, with the fully unbounded range `(-∞, +∞)`.
Changed-context validity is also a premise. Under those premises, the primary
obligation requires explicit rejection. An error or non-unit halt counts as rejection;
fuel exhaustion does not. Applicability establishes a witness to the baseline
validity, baseline acceptance, and changed-context validity premises.

The reference scenario expects Valid for `unboundedRange_claim`,
`unboundedRange_claim_applies`, `unboundedRange_cancel`, and
`unboundedRange_cancel_applies`, producing two PASS combinations. A primary
observation cannot establish PASS without trustworthy linked applicability.
These expectations do not replace fresh execution evidence. The automated
scenario uses the native app API; the public CLI command is a separate check.

The terminal's `Review` path links local retained files. Each
`UP-013-v1-TxM-007` or `UP-013-v1-TxM-008` directory contains
`check-result.json`, execution records, and generated `Types.lean`, `Tx.lean`,
and `Checks.lean`. The shared source snapshot records imported property and
model modules. Generated output remains under ignored `formal/output/` folders.

## Admission and controls

UP-013 admits only the original compiled fixture. Its property-owned rule skips
the second artifact recognized by native TxM-007/008 admission. Native admission
does not support the incompatible vault. These paths generate no
proof obligations and establish no passing property.

The synthetic always-accepting control substitutes `λctx. unit` while preserving
the models, validity premises, range mutation, argument encoding, and CEK bound.
Both main obligations must return Falsified/FAIL and both applicability obligations
must return Valid/PASS. A timeout or compiler/solver error does not satisfy the
control. These intentional failures make the enclosing suite succeed.

The control uses a distinct test identity and clears official property and
binding metadata. Its retained input identifies the original fixture as a
reference input and distinguishes it from the substituted program. The control
does not claim to execute the original validator.

Separate in-memory applicability controls use synthetic observations to check
that missing, inconclusive, or falsified applicability cannot qualify a main PASS.
They check assessment policy without running the solver or proving a validator
property.

`--unit` checks preparation and control structure without invoking the solver.
The default suite checks app/engine execution and retained results. The
property-owned suite checks bindings, artifact selection, and equivalence to the
original formulas. The suites add no automatic Aiken build or duplicate
production validator fixture. See the [workflow test index](../README.md) for
aggregate registration and evidence limits.

## Scope and earlier evidence

The models start with a finite lower bound and no upper bound. UP-013 tests
replacement with the single fully unbounded range, not every range missing a
lower bound. It does not establish a requirement for all validators to reject
unbounded ranges. Broader semantics remain open in
[issue #34](https://github.com/no-witness-labs/contracts-library/issues/34).

The [property scope](../../../Formal/Properties/Universal/UP013/README.md) records
the fixed transaction shapes, artifact restriction, and Blaster trust boundary.
The checks do not establish ledger reachability, arbitrary transaction coverage,
or funds safety. A workflow timeout leaves the affected claim unresolved and
cannot establish explicit rejection or applicability.

The original [standalone guide](../../../Formal/Vesting/Linear/Blueprint/UP013.md)
retains its earlier measured results and direct accepting-control command.
Those records remain historical evidence; neither suite registration nor this
guide claims a fresh proof run or a complete aggregate pass.
