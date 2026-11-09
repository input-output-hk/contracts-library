# Formal documentation map

Start with the guide for the component you are working on:

| Area | Guide |
| --- | --- |
| Run Plutus UPV | [User guide](../Workflow/Docs/USER-GUIDE.md) |
| Maintain properties and models | [Developer guide](../Workflow/Docs/DEVELOPER-GUIDE.md), [property bank](../Formal/Properties/README.md), [model bank](../Formal/TxModels/README.md) |
| Workflow implementation and tests | [Workflow](../Workflow/README.md), [workflow tests](../Workflow/Tests/README.md) |
| Evaluator and ledger model theorems | [Theory](../Formal/Theory/README.md) |
| Shared execution/context helpers | [Support](../Formal/Support/README.md), [shared tests](../tests/README.md) |
| Linear-vesting specification proofs | [Validator guide](../Formal/Vesting/Linear/README.md), [M1.2 suite](../Formal/Vesting/Linear/Tests/README.md) |
| Retained blueprint translator | [Blueprint foundation](BLUEPRINT.md) |

The standalone [UP-002](UP002.md), [UP-007](UP007.md), and [UP-008](UP008.md)
guides retain their property statements, artifact provenance, expected controls,
and historical validation. Other candidate guides live with their existing
definition or test folders and are linked from those owners.

Documentation remains near its owner where practical. `VALIDATION.md` records
the source/dependency revision and checks run; an older successful
result is not fresh validation of a later refactor or dependency change.
