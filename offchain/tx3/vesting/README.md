# Linear Vesting — Tx3 off-chain (planned)

This directory is a placeholder for the **Tx3** implementation of the linear
vesting action set.

Per the PRD (§6.3), v1 ships two reference off-chain implementations — MeshJS
and Tx3 — both implementing the same language-agnostic spec
([`specs/vesting/linear-vesting.md`](../../specs/vesting/linear-vesting.md) §4).
The MeshJS implementation is in [`../meshjs`](../meshjs); the Tx3 implementation
is not started yet.

When implemented, it must cover the same actions against the same pinned
blueprint (validator hash `fa1144f1…`):

- **Lock**: send the bundle to the script with the inline `VestingDatum`.
- **Claim**: spend the vesting UTxO with the `Claim` redeemer, return the
  required remainder to the script (unless fully vested), and set the validity
  range lower bound to the intended "now".
- **Cancel**: spend with the `Cancel` redeemer after `recovery_time`; the locker
  recovers the remainder with no continuing output.

The datum/redeemer CBOR layout to target is documented in
[`../meshjs/src/datum.ts`](../meshjs/src/datum.ts).
