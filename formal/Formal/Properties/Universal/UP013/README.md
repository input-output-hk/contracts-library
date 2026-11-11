# UP-013: experimental fully unbounded-range rejection

UP-013 checks rejection after replacing an accepted context's validity range
with `rangeAlways`, the fully unbounded range `(-∞, +∞)`.
[Definition.lean](Definition.lean) owns one primary `statement` and its supporting
`applicability` predicate. [metadata.json](metadata.json) records the property's
identity, scope, and references.

The statement quantifies over a supplied context family. If the original context
is model-valid and accepted, and the changed context is also model-valid, the
validator must explicitly reject the changed context. Applicability requires a
witness to those premises. The workflow requires trustworthy applicability
evidence before the corresponding primary obligation can establish PASS.

## Run the reference vesting checks

With the [workflow prerequisites](../../../../Workflow/Docs/USER-GUIDE.md#prepare-once)
available, run from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-013 --timeout-ms 300000
```

[Run.lean](Run.lean) selects TxM-007 for Claim and TxM-008 for Cancel. Each
combination uses `validScriptContext`, acceptance within 1,000,000 CEK steps,
and explicit rejection within the same bound. Rejection requires an error or a
non-unit halt; fuel exhaustion does not count. Claim and Cancel have separate
primary and linked applicability obligations:

| Combination | Primary obligation | Applicability obligation |
| --- | --- | --- |
| TxM-007 Claim | `unboundedRange_claim` | `unboundedRange_claim_applies` |
| TxM-008 Cancel | `unboundedRange_cancel` | `unboundedRange_cancel_applies` |

The reference scenario expects two PASS combinations, supported by four Valid
observations. Inspect fresh execution evidence to determine the outcome; the
command and expected results are not a record of a new run. Missing, falsified,
timed-out, or untrusted applicability cannot qualify a primary PASS.

Open the terminal's `Review` path to inspect the generated Lean, results, and
logs. Each combination retains its own directory under the run folder:

```text
validators/linear_vesting.linear_vesting/UP-013-v1-TxM-007/
validators/linear_vesting.linear_vesting/UP-013-v1-TxM-008/
```

Each contains `Generated/Types.lean`, `Generated/Tx.lean`, and
`Generated/Checks.lean`, plus result and execution records. The app also captures
the imported project sources. A zero app exit describes completed orchestration
and retention; inspect the individual results for proof outcomes.

## Scope and admission

The run declaration admits only the original compiled linear-vesting artifact
in `Workflow/Tests/UP012/Inputs/plutus.json`. Native TxM-007/008 admission also
recognizes the reviewed Aiken 1.1.21/stdlib 3.0.0 artifact, but UP-013's
property-owned skip rule excludes it. Unknown artifacts remain unsupported.
Neither case generates a proof obligation or establishes PASS.

Claim has two inputs and two outputs; Cancel has two inputs and one output.
Both models use one vested asset under fixed `policyA`, key credentials, one
signer, and a baseline range with a finite lower bound and no upper bound.
They exclude reference inputs, minting, and withdrawals. Neither model ties its
symbolic script credential to the supplied program's hash. The mutation
changes only the validity range, producing a context outside the baseline family.
Both baseline and changed validity remain explicit premises.

The claim concerns this one fully unbounded range. It does not quantify over
every range without a lower bound or require every validator to reject unbounded
ranges. Its general meaning and relevance remain open in
[issue #34](https://github.com/no-witness-labs/contracts-library/issues/34).
The existing CLI defaults and all-enabled example switch file include UP-013.
Registration does not establish that the property suits a particular protocol.

Results retain Blaster's SMT trust boundary and the fixed model/artifact limits.
They do not establish arbitrary transaction coverage, ledger reachability,
source correspondence, or funds safety. The CEK bound is separate from ledger
CPU and memory budgets and the CLI's wall-clock timeout. A timeout or
compiler/solver error leaves the affected claim unresolved.

## Tests and provenance

The [validation record](VALIDATION.md) records execution evidence and its limits.

Focused commands from `formal/`:

```sh
lake exe workflow_declarative_up013_tests
lake exe workflow_up013_tests
lake exe workflow_up013_tests --unit
```

[Tests.lean](Tests.lean) checks property/model bindings, the original-artifact
restriction, and equivalence to the preserved Claim and Cancel formulas.
The [workflow scenario](../../../../Workflow/Tests/UP013/README.md) uses the native
catalogue and app API to check execution, retained output, skip behavior, and
synthetic always-accepting controls. The public CLI command above is a separate
end-to-end check. Both new suites belong to the workflow aggregate; registration
does not claim that an aggregate run passed.

The [standalone guide](../../../Vesting/Linear/Blueprint/UP013.md) preserves
the original statements, attribution, dependency pins, measured results, and
accepting control. Those historical results do not establish a fresh workflow
run. The integration preserves the native models and 1,000,000-step allowance;
broader model authoring and integration remain tracked in issues #89 and #96.
