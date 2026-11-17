# M1.1 standalone checkpoints

These folders retain validator-specific inputs and helpers for standalone M1.1
property checks. Their proof invocations, controls, and fixtures remain owned by
[Properties/UPxxx/Tests/Standalone](../Properties/README.md#test-ownership).

| Folder | Candidate guides |
| --- | --- |
| `LinearVesting/` | [UP-000](LinearVesting/UP000.md), [UP-004](LinearVesting/UP004.md), [UP-010](LinearVesting/UP010.md), [UP-011](LinearVesting/UP011.md), [UP-012](LinearVesting/UP012.md), [UP-013](LinearVesting/UP013.md), [UP-014](LinearVesting/UP014.md), [UP-015](LinearVesting/UP015.md); [UP-007](../docs/UP007.md) and [UP-008](../docs/UP008.md) |
| [Vault](Vault/README.md) | UP-009 hashed-datum checkpoint |
| [Settings](Settings/README.md) | UP-016 mint-quantity checkpoint |

The vesting inputs here support M1.1 property experiments. The [M1.2 specification
proofs and test suite](../../LinearVesting/README.md) have separate ownership and
coverage. Standalone jobs are explicit commands; the workflow aggregate does not
run them all. Recorded falsifications, incomplete proofs, and timeouts retain
their original meanings after relocation.
