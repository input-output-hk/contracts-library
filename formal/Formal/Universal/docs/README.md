# M1.1 documentation map

M1.1 owns the universal-property verifier, reusable banks, and standalone
checkpoints. Start with the guide for the component you are working on:

| Area | Guide |
| --- | --- |
| Run Plutus UPV | [User guide](../Workflow/Docs/USER-GUIDE.md) |
| Maintain properties and models | [Developer guide](../Workflow/Docs/DEVELOPER-GUIDE.md), [property bank](../Properties/README.md), [model bank](../TxModels/README.md) |
| Workflow implementation and tests | [Workflow](../Workflow/README.md), [workflow tests](../Workflow/Tests/README.md) |
| Evaluator and ledger model theorems | [Theory](../Theory/README.md) |
| M1.1 execution/context helpers | [Support](../Support/README.md), [utility tests](../tests/README.md) |
| Linear-vesting specification proofs | [Validator guide](../../LinearVesting/README.md), [M1.2 suite](../../LinearVesting/Tests/README.md) |
| Retained blueprint translator | [Blueprint foundation](BLUEPRINT.md) |

The native [UP-007 guide](../Properties/UP007/README.md) and
[UP-008 guide](../Properties/UP008/README.md) cover their Claim-only
workflows and expected official FAIL results. The standalone
[UP-002](UP002.md), [UP-007](UP007.md), and [UP-008](UP008.md)
guides retain their property statements, artifact provenance, expected controls,
and historical validation. Other candidate guides live with their existing
definition or test folders and are linked from those owners.

The linear-vesting specification proofs belong to M1.2. Vesting artifacts used
by M1.1 properties and workflow tests remain M1.1 fixtures.

Documentation remains near its owner where practical. `VALIDATION.md` records
the source/dependency revision and checks run; an older successful
result is not fresh validation of a later refactor or dependency change.
