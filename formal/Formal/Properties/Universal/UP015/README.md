# UP-015: experimental output-reversal acceptance

[Definition.lean](Definition.lean) defines the primary `statement`, the
`reverseOutputs` context transformation, and the supporting `applicability`
predicate. The transformation reverses `txInfoOutputs` and preserves every other
context field. The statement takes a context family and validity/acceptance
predicates. A valid accepted original must remain accepted when its reversal is
also valid.

The workflow binds this property only to TxM-007 and two exact unparameterized
linear-vesting artifacts shared with UP-012. These are the original PR #55 fixture
and the reviewed vault-demo build using Aiken 1.1.21 with stdlib 3.0.0. Unknown compiled
artifacts remain unsupported. The Claim model contains two outputs,
one signer, and one vested asset. Reversal therefore swaps the continuation and
payout outputs. Acceptance uses the existing 1,000,000 CEK-step allowance; this is
not a ledger CPU or memory budget.
The original input remains `Workflow/Tests/UP012/Inputs/plutus.json`; the second
snapshot is `Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json`.
The native model reads its artifact allowlist from
[Artifacts/LinearVesting.lean](../../../TxModels/Artifacts/LinearVesting.lean).
Shared program preparation supplies the executed artifact. The test profile
retains the earlier comparison path. The property definition, native model,
and evaluation bound remain unchanged.

The applicability obligation requires a valid accepted original, a valid reversed
context, and an output list that differs after reversal. This last
condition deliberately strengthens the original PR #62 applicability formula.
The primary acceptance proposition and evaluation bound remain unchanged. An
identity transformation cannot supply this applicability witness.

[metadata.json](metadata.json) records the property's identity and scope.
[Run.lean](Run.lean) instructs the shared generator to emit `reverseOutputs_claim`
and its linked `reverseOutputs_claim_applies` obligation. The generator unfolds
the native definition before invoking Blaster.
[Workflow.Tests.Legacy.Candidates.UP015](../../../../Workflow/Tests/Legacy/Candidates/UP015.lean) remains a legacy comparison
adapter. The source candidate is PR #62 at
`7c5dce717ca1d2b1d975c1c1b044bc48c07e0687`.

This integration excludes the singleton Cancel reversal and the duplicate
two-output rotation. It does not cover wider output permutations, arbitrary
transaction models, or other validators whose behavior depends on output
indices. These modeled checks do not establish deployed-ledger reachability or
general audit readiness.
General definition, model-authoring, and integration work remains open in issues
#23, #33, #36, #89, and #96.

## Property-owned execution

[Run.lean](Run.lean) selects TxM-007 and declares the goals for the shared
Lean generator. Its `ModelUse` entry owns the model `id` and reviewed pairing
`limitations`. [Tests.lean](Tests.lean) checks goal parity with the legacy adapter
and exact retention of the reviewed combination record. It also provides a
labeled counterfactual rejection control.

From `formal/`:

```sh
lake exe workflow_declarative_up015_tests
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-015 --timeout-ms 300000
```

The public CLI evaluates these run instructions and compiles the selected model
through shared Lean discovery. Model coverage, applicability, and proof bounds
remain as described above. The [validation record](VALIDATION.md) preserves
historical goal-parity and proof/control evidence at its recorded revisions;
it does not establish fresh validation of the current Lean-only implementation.
