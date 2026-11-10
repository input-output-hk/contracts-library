# UP-004: bounded model-valid rejection

UP-004 asks whether at least one context in a supplied family satisfies the
configured validity and explicit-rejection predicates.
[Definition.lean](Definition.lean) states this existential property without
choosing a validator or transaction model. [metadata.json](metadata.json) records
its identity, scope, and references.

## Run the reference vesting checks

With the [workflow prerequisites](../../../../Workflow/Docs/USER-GUIDE.md#prepare-once)
available, run from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-004
```

[Run.lean](Run.lean) selects TxM-007 for Claim and TxM-008 for Cancel. Each
combination generates one primary obligation, `someRejected_claim` or
`someRejected_cancel`. Each asks for a model-valid context that the validator
explicitly rejects within 1,000,000 CEK steps. Rejection means an error or a
non-unit halt; fuel exhaustion does not count. The existential statement includes
validity and rejection of the same witness, so these checks need no separate
applicability obligation.

Open the terminal's `Review` path to inspect the generated Lean, check results,
and logs. Under its run folder, each combination has a directory:

```text
validators/linear_vesting.linear_vesting/UP-004-v1-TxM-007/
validators/linear_vesting.linear_vesting/UP-004-v1-TxM-008/
```

Each contains `Generated/Types.lean`, `Generated/Tx.lean`, and
`Generated/Checks.lean`, plus retained result and execution files. The reference
scenario expects two PASS results. Inspect fresh execution evidence to confirm
the outcome; a zero app exit alone does not mean that both checks passed.

## Scope and admission

The run declaration admits only the original compiled linear-vesting artifact in
`Workflow/Tests/UP012/Inputs/plutus.json`. Native model admission also recognizes
a second Aiken 1.1.21/stdlib 3.0.0 artifact, but UP-004's property-owned skip rule
excludes it. That combination produces no proof obligation or passing verdict.
Unknown artifacts remain unsupported by native admission.

Claim has two inputs and two outputs; Cancel has two inputs and one output.
Both native models use one vested asset under fixed `policyA`, key credentials,
one signer, and a validity range with a finite lower bound and no upper bound.
They exclude reference inputs, minting, and withdrawals. The script credential
remains symbolic; neither model ties it to the supplied program's hash.
The check uses `validScriptContext` from the Lean ledger model over these shapes.

PASS establishes bounded model-valid rejection existence under Blaster's SMT
trust boundary. It does not establish deployed-ledger reachability, arbitrary
action coverage, correct authorization, rejection of every invalid transaction,
or funds safety. FAIL does not establish that the program accepts every context.
A workflow timeout or compiler/solver error leaves the claim unresolved; a script
error is an explicit rejection. The CEK-step allowance is separate from ledger CPU
and memory budgets and the CLI's wall-clock timeout.
This route adds no minimum ADA requirement and prints no rejected transaction witness.

## Tests and provenance

The [validation record](VALIDATION.md) documents the tested revision and results.

From `formal/`:

```sh
lake exe workflow_declarative_up004_tests
lake exe workflow_up004_tests
```

[Tests.lean](Tests.lean) owns property/model checks, including equivalence with
the original expanded Claim and Cancel formulas and artifact selection.
[Tests/Parity.lean](Tests/Parity.lean) also proves that zero CEK fuel cannot
establish rejection or rejection existence. The
[workflow scenario](../../../../Workflow/Tests/UP004/README.md) checks the native
catalogue, app, engine, retained output, skips, and synthetic always-accepting
controls. A separate 1 ms app-deadline scenario expects two TIMEOUT/INCONCLUSIVE
results with retained evidence and performs no proof retry. Both suites belong
to the workflow aggregate. The public CLI command
above provides a separate end-to-end check.

The [standalone record](../../../Vesting/Linear/Blueprint/UP004.md) preserves the
original claims, PR #44/#56 attribution, dependency pins, measured results, and
always-accepting control. Those historical results do not establish a fresh
workflow run. The integration reuses the native models without changing the
original propositions or their 1,000,000-step bound. Minimum ADA, witness
presentation, and broader model/action coverage remain separate work under
[issue #25](https://github.com/no-witness-labs/contracts-library/issues/25) and
the model/integration follow-ups.
