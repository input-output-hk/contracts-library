# UP-012: experimental signer-removal rejection

[Definition.lean](Definition.lean) contains one primary `statement` and its
supporting `applicability` predicate. They take a transaction-context family and
the validity/acceptance/rejection predicates used by a configured check.
[metadata.json](metadata.json) holds the property's maintained identity, scope,
and references; Claim, Cancel, and key-datum spend use that shared property record.

The statement quantifies over the model's inputs. If the original context passes
the supplied validity predicate, is accepted, has a nonempty signer list, and the
context with its first signer removed also passes that predicate, the changed
context must be rejected. Applicability requires a witness to those premises.

The bindings use TxM-007 (Claim), TxM-008 (Cancel), and TxM-009
(single-signer key-datum spend), the model's
`validScriptContext` predicate, and explicit rejection within 1,000,000 CEK steps.
Native model admission allows two exact compiled linear-vesting artifacts: the
original PR #55 fixture and the reviewed vault-demo build using Aiken 1.1.21 with
stdlib 3.0.0. TxM-009 uses reusable structural admission and validates the actual compiled
program; it requires no artifact allowlist entry. Unknown schema constraints
remain unsupported for that model. These are three applications of one property,
with separate applicability obligations. Owner, signer, and recipient vary
independently in TxM-009; no owner-equals-signer premise is added.

The current models contain one signer, so the change removes the sole signer.
For this example, assume that the baseline contains only the intended required
signer, with no unrelated extra signers. This is an assumption about the scenario's
intended use, not an additional Lean premise or a requirement inferred by the tool.

The check establishes dependence on that signer within the supplied model. It
does not identify the correct owner or prove that the signer represents the
protocol's intended authorization rule. A validator that requires any signature,
including the wrong key, can satisfy signer-removal rejection while violating
its intended owner requirement. Multiple signers, unrelated extras, alternative
authorization, and threshold policies remain outside this example's coverage.

Keep this as an experimental workflow test. Its suitability as a universal
property and the meaning of a required signer remain open in
[issue #33](https://github.com/no-witness-labs/contracts-library/issues/33).
The adapter unfolds the shared definition before invoking Blaster. Workflow tests
keep the previous expanded formulas as independent equivalence/negative-control
fixtures. Model applications stay in the binding/test layer rather than separate
Claim and Cancel property definitions.

## Property-owned execution

[Run.lean](Run.lean) owns the run instructions and enabled model entries. Each
`ModelUse` entry names a model through `id` and retains the reviewed `limitations`
of that pairing. Shared Lean discovery supplies imports and execution bindings
from this one list. [Tests.lean](Tests.lean) checks goal parity with the legacy
adapter and exact retention of the reviewed combination records.

From `formal/`:

```sh
lake exe workflow_declarative_tests
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-012 --timeout-ms 300000
```

The [execution guide](../../../../Workflow/Declarative/README.md) describes
discovery, the public command, and retained compatibility paths.
