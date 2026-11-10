# UP-000: bounded model-valid acceptance

UP-000 asks whether at least one context in a supplied family satisfies the
configured validity and bounded acceptance predicates.
[Definition.lean](Definition.lean) states this existential property without
choosing a validator or transaction model. [metadata.json](metadata.json) records
its identity, scope, and references.

## Run the reference vesting checks

With the [workflow prerequisites](../../../../Workflow/Docs/USER-GUIDE.md#prepare-once)
available, run from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-000
```

[Run.lean](Run.lean) selects TxM-007 for Claim and TxM-008 for Cancel. Each
combination generates one primary obligation, `someAccepted_claim` or
`someAccepted_cancel`. Each asks for a model-valid accepted context within
1,000,000 CEK steps. Existence is the primary claim, so the check needs no separate
applicability obligation.

Open the terminal's `Review` path to inspect the generated Lean, check results,
and logs. Under its run folder, each combination has a directory:

```text
validators/linear_vesting.linear_vesting/UP-000-v1-TxM-007/
validators/linear_vesting.linear_vesting/UP-000-v1-TxM-008/
```

Each contains `Generated/Types.lean`, `Generated/Tx.lean`, and
`Generated/Checks.lean`, plus retained result and execution files. `Types.lean`
embeds the selected program and evaluator interface; `Tx.lean` aliases the
native model; `Checks.lean` contains the concrete existential goal. The reference
scenario expects two PASS results. This expectation does not replace fresh
execution evidence, and a zero app exit alone does not mean that both checks passed.

## Scope and admission

The run declaration admits only the original compiled linear-vesting artifact in
`Workflow/Tests/UP012/Inputs/plutus.json`. The native model allowlist also contains
a second Aiken 1.1.21/stdlib 3.0.0 artifact, but UP-000's property-owned skip rule
excludes it. That combination produces no proof obligation or passing verdict.
Unknown artifacts remain unsupported by native admission. The general definition
does not make other validators runnable through this binding.

Claim has two inputs and two outputs; Cancel has two inputs and one output.
Both native models use one vested asset under fixed `policyA`, key credentials,
one signer, and a validity range with a finite lower bound and no upper bound.
They exclude reference inputs, minting, and withdrawals. The check uses
`validScriptContext` from the Lean ledger model over these fixed shapes.

PASS establishes bounded model-valid acceptance under Blaster's SMT trust
boundary. It does not establish deployed-ledger reachability, universal action
coverage, or funds safety. The CEK-step allowance is separate from ledger CPU
and memory budgets and the CLI's wall-clock timeout. This route adds no minimum
ADA requirement and prints no accepted transaction witness.

## Tests and provenance

The [validation record](VALIDATION.md) documents the tested revision and results.

From `formal/`:

```sh
lake exe workflow_declarative_up000_tests
lake exe workflow_up000_tests
```

[Tests.lean](Tests.lean) owns property/model checks, including equivalence with
the original expanded Claim and Cancel formulas and artifact selection. The
[workflow scenario](../../../../Workflow/Tests/UP000/README.md) checks the native
catalogue, app, engine, retained output, skips, and synthetic always-error controls.
Both suites belong to the workflow aggregate. The public CLI command above
provides a separate end-to-end check; the retained standalone rejecting control
also remains available through its original proof command.

The [standalone record](../../../Vesting/Linear/Blueprint/UP000.md) preserves the
original claims, PR #44/#53 attribution, dependency pins, measured results, and
always-error control. Those historical results do not establish a fresh workflow
run. The integration reuses the native model bank without changing the original
propositions or their 1,000,000-step bound. Broader action reachability, minimum
ADA, witness presentation, and other model/artifact coverage remain separate
work under [issue #22](https://github.com/no-witness-labs/contracts-library/issues/22)
and the model/integration follow-ups.
