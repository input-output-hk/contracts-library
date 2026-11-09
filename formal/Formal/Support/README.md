# Shared execution and compatibility helpers

This folder contains execution predicates, context operations, compatibility
aliases, and helpers used by existing candidate implementations.

| File | Role |
| --- | --- |
| `Execution.lean` | Bounded execution and signatory operations |
| `Compatibility.lean` | Compatibility aliases for native models and transaction builders |
| `CandidateHelpers.lean` | Shared context mutations used by standalone candidates |
| `ReturnDatum.lean` | Existing return-output datum predicate |

Evaluator and ledger-model theorems and their `U-*` catalogue are in
[Theory](../Theory/README.md). Reusable validator properties and run declarations
are in [Properties](../Properties/README.md). Shared operations use the
`Formal.Support` namespace, with builder aliases under `Formal.Support.TxBuilder`
and the return-datum predicate under `Formal.Support.ReturnDatum`.

Import `Formal.Support.Execution` for evaluator/context operations without model
catalogue imports. The `Formal.Support.Compatibility` module provides the older
model/builder aliases for existing consumers. Broader candidate migration remains
a separate task.
