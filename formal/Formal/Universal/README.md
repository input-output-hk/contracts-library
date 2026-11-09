# Shared execution and compatibility helpers

This folder contains execution predicates, context operations, compatibility
aliases, and helpers used by existing candidate implementations.

| File | Role |
| --- | --- |
| `Execution.lean` | Bounded execution and signatory operations |
| `Properties.lean` | Compatibility aliases for native models and transaction builders |
| `CandidateHelpers.lean` | Shared context mutations used by standalone candidates |
| `ReturnDatum.lean` | Existing return-output datum predicate |

Evaluator and ledger-model theorems and their `U-*` catalogue are in
[Theory](../Theory/README.md). Reusable validator properties and run declarations
are in [Properties](../Properties/README.md). The helper folder's eventual naming
and candidate migration remain separate decisions.
