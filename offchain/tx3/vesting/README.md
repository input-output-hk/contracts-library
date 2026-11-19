# Linear Vesting — Tx3 off-chain (planned)

This directory is a placeholder for the **Tx3** implementation of the linear
vesting action set.

Per the PRD (§6.3), v1 ships two reference off-chain implementations — MeshJS
and Tx3 — both implementing the same language-agnostic spec
([`docs/vesting/spec.md`](../../../docs/vesting/spec.md) §4).
The MeshJS implementation is in [`../../meshjs`](../../meshjs); the Tx3 implementation
is not started yet.

Implement the same actions against the validator pinned by MeshJS. [Pinned blueprint](../../meshjs/lib/src/vesting/blueprint.ts)

- **Lock**: send the bundle to the script with the inline `VestingDatum`.
- **Claim**: spend the vesting UTxO with the `Claim` redeemer and a finite
  validity lower bound. In a partial claim, return the required remainder to
  the input's full address with the same inline datum.
- **Cancel**: spend with the `Cancel` redeemer after `recovery_time`; the locker
  recovers the remainder with no continuing output.

The MeshJS encoders define the datum and redeemer CBOR layout. [Encoders](../../meshjs/lib/src/vesting/datum.ts)
