# Shared execution and compatibility helpers

This folder contains execution predicates, context operations, compatibility
aliases, and helpers used by existing candidate implementations.

| File | Role |
| --- | --- |
| `Execution.lean` | Bounded execution and signatory operations |
| `Continuations.lean` | Native continuation selection, mutation of the first continuation, and redirection shared by UP-011 and UP-014 |
| `Compatibility.lean` | Compatibility aliases for native models and transaction builders |
| `CandidateHelpers.lean` | Shared context mutations used by standalone candidates |
| `ReturnDatum.lean` | Existing return-output datum predicate |

Evaluator and ledger-model theorems and their `U-*` catalogue are in
[Theory](../Theory/README.md). Reusable validator properties and run declarations
are in [Properties](../Properties/README.md). Shared operations use the
`Formal.Universal.Support` namespace, with continuation helpers under
`Formal.Universal.Support.Continuations`, builder aliases under `Formal.Universal.Support.TxBuilder`,
and the return-datum predicate under `Formal.Universal.Support.ReturnDatum`.

Import `Formal.Universal.Support.Execution` for evaluator/context operations without model
catalogue imports. `Formal.Universal.Support.Continuations` owns the shared native
continuation helpers; UP-011 retains its existing helper API and semantics.
The `Formal.Universal.Support.Compatibility` module provides the older model/builder
aliases for existing consumers. Broader candidate migration remains
a separate task.

[Earlier validation](VALIDATION.md) records the original support-folder relocation.
The [UP-014 validation record](../Properties/UP014/VALIDATION.md) covers
the later continuation-helper extraction and its UP-011/UP-014 regression checks.
