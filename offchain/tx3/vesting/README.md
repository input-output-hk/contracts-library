# Linear Vesting — Tx3 off-chain

Reference **Tx3** implementation of the linear vesting action set, mirroring the
on-chain validator in
[`onchain/validators/linear_vesting.ak`](../../../onchain/validators/linear_vesting.ak)
(reusable logic in
[`onchain/lib/vesting/`](../../../onchain/lib/vesting/)) and the MeshJS builders
in [`offchain/meshjs/lib/src/vesting`](../../meshjs/lib/src/vesting). The
language-agnostic behavior is specified in
[`docs/vesting/spec.md`](../../../docs/vesting/spec.md).

A vesting instance is a single UTxO at the (unparameterized) `linear_vesting`
script address carrying the immutable `VestingDatum` inline. The schedule
(`start_time < end_time < recovery_time`, POSIX milliseconds) is fixed at lock
time; on-chain `now` is read from the transaction's validity lower bound, so
every claim/cancel carries the slot to use as the reference instant.

## Action set

| Template | Purpose |
| --- | --- |
| `lock` | The locker sends the bundle to the script with the inline `VestingDatum`. Pure off-chain construction — no script runs. |
| `claim` | The beneficiary withdraws the vested portion; a continuation at the script address reproduces the datum verbatim and keeps the required remainder. |
| `claim_full` | The beneficiary takes the whole bundle once `now >= end_time`; no continuation (I4). |
| `cancel` | The locker recovers the remainder after `recovery_time` (strictly); no continuation. |

Each builder is a Tx3 transaction template in [`main.tx3`](./main.tx3); the
TypeScript client is generated from it with `trix codegen`.

## Parameters (`env`)

| Env value | Meaning |
| --- | --- |
| `vesting_script` | The pinned `linear_vesting` validator, single-CBOR flat form. The validator is unparameterized; its Blake2b-224 hash is pinned in [`offchain/meshjs/lib/src/vesting/blueprint.ts`](../../meshjs/lib/src/vesting/blueprint.ts) (`95da2178…`). |

Parties bound at runtime: `Locker` (locks, cancels), `Beneficiary` (claims),
and `Vesting` (the script address). `Locker` and `Beneficiary` are bound to the
key credentials the datum records.

## Scope notes

Same reduction pattern as the other Tx3 references ([`../dao`](../dao),
[`../smart_wallet`](../smart_wallet)) — the on-chain code is strictly more
permissive than this reference:

- **Key-authorized paths only.** The on-chain `authorization.is_authorized`
  accepts a key credential (a required signer) or a script credential (a
  withdraw-0 reward withdrawal). Tx3 has no runtime key-vs-script branch and
  cannot wire a withdrawal for a script hash supplied inside the datum, so
  this protocol implements the key-authorized paths only: the party bound as
  `Beneficiary`/`Locker` must own the datum's key credential. Script
  beneficiaries/lockers go through the MeshJS builders (`authorizer`).
- **Ada-only bundles.** Tx3 value expressions cannot enumerate an arbitrary
  asset list, so `lock` vests lovelace only. Multi-asset schedules go through
  the MeshJS builders.
- **Single-input claims.** Each template spends exactly one vesting instance.
  Batching several instances stays legal on-chain (spec §5.1); the multi-input
  shapes — including the instance-merge attacks they close — are exercised by
  the [MeshJS e2e suite](../../meshjs/e2e/test/vesting.e2e.test.ts).
- **Caller-supplied data.** The datum (reproduced byte-for-byte on the
  continuation) and the required remainder (`total - vested(now)`, computed
  with the MeshJS `vestedQuantity` helper and floored at min-UTxO) are
  parameters: Tx3 value expressions cannot evaluate the on-chain floor
  division. Extra ada beyond the remainder is schedule-unprotected surplus
  (spec §7).
- **Lock is the builder's responsibility** (spec §4.1 / I7): a well-formed
  schedule and a value covering every `vesting` entry are never checked
  on-chain.

## Devnet tests

[`tests/devnet.test.ts`](./tests/devnet.test.ts) boots an ephemeral trix
devnet and drives the client end-to-end: lock → partial claim (asserting the
continuation holds the exact required remainder computed from the validity
lower bound), full claim with no continuation, locker recovery, and the
must-reject shapes — over-claim, tampered continuation datum, missing
beneficiary signature, a cancel whose lower bound sits exactly at
`recovery_time` (strict boundary), and a cancel by a non-locker — each
asserted to fail for the right reason and leave the vesting UTxO untouched.
Run it from [`offchain/tx3`](../) with `npm run test:vesting`.