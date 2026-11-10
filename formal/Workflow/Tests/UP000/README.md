# UP-000 workflow scenario

This scenario exercises the native catalogue, app, and engine for the bounded model-valid acceptance
property in [UP000/Definition.lean](../../../Formal/Properties/Universal/UP000/Definition.lean).
It reuses the original compiled vesting fixture at
[UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json), native TxM-007 Claim and
TxM-008 Cancel, and the original 1,000,000 CEK-step allowance.

From `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-000
lake exe workflow_up000_tests
lake exe workflow_up000_tests --unit
lake exe workflow_declarative_up000_tests
```

The public run selects two combinations. `someAccepted_claim` and
`someAccepted_cancel` each ask whether a context satisfies `validScriptContext`
and the validator accepts it within the bound. These are primary existential
goals, with no separate applicability jobs. The expected reference outcome is
two PASS results; a timeout or an error leaves the affected claim unresolved.
Confirm that expectation with fresh execution evidence. The public CLI command
is a separate check from the automated app scenario.

The terminal prints a `Review` path to a local navigation README and an `Index`
path to `run.json`. Each `UP-000-v1-TxM-007` or `UP-000-v1-TxM-008` directory retains
`check-result.json`, execution records, and the generated `Types.lean`, `Tx.lean`,
and `Checks.lean`. The shared source snapshot records the imported property and
native models. These files stay under ignored `formal/output/` folders.

The property-owned suite checks the original artifact, the second native-allowlist
artifact, an incompatible vault, and equivalence to the original formulas. The
workflow suite expects two PASS results for the original artifact and tests
both skip paths. UP-000's run declaration skips the second artifact even though
native model admission recognizes it. Native admission does not support the vault.
Neither skip establishes a passing property.

The workflow suite also substitutes a synthetic always-error program while
keeping the model-valid existence questions and CEK bound. Its two control goals
must return Falsified/FAIL; a timeout or error does not satisfy the control. These
intentional failures make the enclosing suite succeed. The control uses a distinct
identity and clears official property/binding metadata. It retains
`original-input.json` as a reference, plus `control-result.json`, `execution.json`,
generated sources, and logs. It does not claim to execute the original program.

`--unit` checks control preparation without invoking the solver. The default
workflow suite checks app/engine execution and retained output; it adds no
automatic Aiken build or duplicate production validator fixture.

The original [standalone guide](../../../Formal/Vesting/Linear/Blueprint/UP000.md)
retains the earlier measured proof results and synthetic always-error control.
That control expects two Falsified observations and is a separate command;
its deliberate proof failure does not make it a public runnable property.

The [property scope](../../../Formal/Properties/Universal/UP000/README.md) describes
the fixed models and original-artifact restriction. Passing these checks does not
establish ledger reachability, arbitrary action coverage, or funds safety. The
integration adds no minimum ADA requirement and prints no accepted transaction
witness. Workflow test success alone does not establish general readiness.
