# M1.1 universal-property verification

M1.1 owns Plutus UPV, the reusable property and transaction-model banks, their
support code, and their tests. Run public commands from the Lake workspace at
`formal/`; start with the [user guide](Workflow/Docs/USER-GUIDE.md).

| Owner | Contents |
| --- | --- |
| [Properties](Properties/README.md) | Direct `UPxxx/` folders with definitions, metadata, run declarations, and property tests; category remains metadata |
| [TxModels](TxModels/README.md) | Reusable transaction models and model metadata |
| [Workflow](Workflow/README.md) | CLI, preparation, execution, reporting, and app/engine tests |
| [Support](Support/README.md) | M1.1 execution predicates, context operations, and compatibility helpers |
| [Theory](Theory/README.md) | Evaluator and ledger model theorems with existing `U-*` identities |
| [Standalone](Standalone/README.md) | Retained LinearVesting, Vault, and Settings candidate checkpoints |
| [docs](docs/README.md), [tests](tests/README.md), `scripts/` | M1.1 guides, utility tests, and blueprint translation |

The maintained catalogue has ten properties, twenty property/model combinations,
and nine models. `./plutus-upv test` registers 39 suites. These counts describe
registration; they do not establish general property or model readiness.

The [linear-vesting specification proofs and suite](../LinearVesting/README.md)
belong to M1.2. A vesting artifact used by an M1.1 property or workflow test remains
an M1.1 fixture. Only common predicates and generic process execution belong in
[Shared](../Shared/README.md).

Historical validation retains its original revisions, model bounds, artifacts,
and outcomes. Moving an implementation or updating a command path does not rerun
its proofs or convert a timeout into a result.
