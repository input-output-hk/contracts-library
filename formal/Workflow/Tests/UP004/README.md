# UP-004 workflow scenario

This scenario exercises the native catalogue, app, and engine for the bounded
model-valid rejection property in
[UP004/Definition.lean](../../../Formal/Properties/Universal/UP004/Definition.lean).
It reuses the original compiled vesting fixture at
[UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json), native TxM-007 Claim and
TxM-008 Cancel, and the original 1,000,000 CEK-step allowance.

From `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-004
lake exe workflow_up004_tests
lake exe workflow_up004_tests --unit
lake exe workflow_declarative_up004_tests
```

The public run selects two combinations. `someRejected_claim` and
`someRejected_cancel` each ask whether a context satisfies `validScriptContext`
and the validator rejects it with an error or a non-unit halt within the bound.
Fuel exhaustion never counts as rejection. These primary existential goals need
no separate applicability jobs.

The expected reference outcome is two PASS results. A workflow timeout or
compiler/solver error leaves the affected claim unresolved; a script error is an
explicit rejection. Confirm the outcome with
fresh execution evidence. The public CLI command is a separate check from the
automated native app scenario.

The terminal prints a `Review` path to a local navigation README and an `Index`
path to `run.json`. Each `UP-004-v1-TxM-007` or `UP-004-v1-TxM-008` directory retains
`check-result.json`, execution records, and the generated `Types.lean`, `Tx.lean`,
and `Checks.lean`. The shared source snapshot records the imported property and
native models. These files stay under ignored `formal/output/` folders.

The property-owned suite checks the original artifact, the second native-allowlist
artifact, an incompatible vault, and equivalence to the original formulas. The
workflow suite expects two PASS results for the original artifact and tests
both skip paths. UP-004 skips the second artifact even though native model
admission recognizes it. Native admission does not support the vault. Neither
skip establishes a passing property.

A controlled app run sets a 1 ms execution deadline and expects two TIMEOUT
results with INCONCLUSIVE assessments and retained generated files and logs.
It performs no proof retry. This operational test is separate from the
[zero-fuel proofs](../../../Formal/Properties/Universal/UP004/Tests/Parity.lean),
which show that CEK fuel exhaustion cannot establish rejection existence.

The workflow suite substitutes a synthetic always-accepting program while keeping
the model-valid rejection-existence questions and CEK bound. Its two control goals
must return Falsified/FAIL; a workflow timeout or compiler/solver error does not
satisfy the control.
These intentional failures make the enclosing suite succeed. The control uses
a distinct identity and clears official property/binding metadata. Its retained
files distinguish the original input reference from the substituted program.
It does not claim to execute the original program.

`--unit` checks control preparation without invoking the solver. The default
workflow suite checks app/engine execution and retained output; it adds no
automatic Aiken build or duplicate production validator fixture.

The original [standalone guide](../../../Formal/Vesting/Linear/Blueprint/UP004.md)
retains earlier measured results and its separate always-accepting control command.
The [property scope](../../../Formal/Properties/Universal/UP004/README.md) describes
the fixed models and original-artifact restriction. Passing these checks does not
establish ledger reachability, arbitrary action coverage, or funds safety. The
integration adds no minimum ADA requirement and prints no rejected transaction
witness. Workflow test success alone does not establish general readiness.
