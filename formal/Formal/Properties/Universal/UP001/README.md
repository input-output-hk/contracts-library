# UP-001: bounded nonacceptance

[Definition.lean](Definition.lean) states that no context in the supplied family
satisfies the configured acceptance predicate. [metadata.json](metadata.json)
records the maintained definition's identity, explanation, scope, and references.

The current adapter checks each purpose absent from the selected validator's
declared handlers, using the corresponding open transaction model. It supplies
acceptance within 5,000,000 CEK steps. Fuel exhaustion satisfies nonacceptance;
this does not establish explicit rejection. The models add no ledger-validity
premise, so a counterexample may not correspond to a ledger-valid transaction.

The definition is independent of a particular validator or purpose model.
Registered bindings determine the actual target, family, and evaluator bound.
The adapter unfolds the shared definition before invoking Blaster. Kernel-checked
equivalences in the workflow tests compare all six applications to the previous
expanded formulas.
