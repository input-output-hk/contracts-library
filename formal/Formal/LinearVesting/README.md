# Linear vesting: formal proofs

Lean proofs about the compiled linear-vesting spending validator.
The source of truth is the spec in [`spec.md`](../../../docs/vesting/spec.md), and the on-chain code is [`linear.ak`](../../../onchain/lib/vesting/linear.ak).
For the toolchain and build, see the [`formal/` README](../../README.md).

## Approach

`Spec.lean` is an executable spec: `specAccepts d r ctx` says whether a transaction should be accepted.
The proofs have three parts.

1. **Agreement** (Blaster, bounded): the compiled validator accepts exactly what the spec accepts, on the transaction shapes in `TxBuilder.lean`.
   Each direction is separate: `Sound` (validator accepts ⇒ spec accepts) and `Complete` (spec accepts ⇒ validator accepts).
2. **Spec properties** (plain Lean, unbounded): safety, acceptance, and chains of claims, proved about `specAccepts` for every transaction.
3. **Corollaries and tests**: spec properties carried to the validator through agreement, and fixed transactions run through both.

An adapted validator that only adds restrictions needs to re-prove `Sound` only; every rejection then carries over through `rejects_of_sound`.

## Modules

| Module | Contents | Checked by |
| --- | --- | --- |
| `Spec` | `vested`, `required`, the datum and redeemer encodings, `specAccepts` | Blaster (arithmetic lemmas) |
| `Script` | the compiled validator, `spendValidator` | |
| `TxBuilder` | the transaction shapes, and `Sound`, `Complete`, `Agrees` | |
| `CancelSound`, `CancelComplete` | agreement on cancels | Blaster |
| `ClaimSound`, `ClaimComplete` | agreement on claims, one theorem per shape | Blaster |
| `Robustness` | exact conditions (`claim_iff`, `cancel_iff`), `*_requires_*`, `reject_*` | Lean kernel |
| `Functionality` | `accept_*` | Lean kernel |
| `MultiTx` | chains of claims, `chain_*` | Lean kernel |
| `Corollaries` | spec properties for `spendValidator` | Blaster |
| `Tests` | fixed transactions, `spec_*` and `validator_*` | Blaster |

## Transaction shapes

| Theorem | Shape |
| --- | --- |
| `cancel_*` | the vesting input, then any inputs and outputs |
| `claim_*` | key beneficiary, the vesting input only |
| `claim_*_script` | script beneficiary, the vesting input only |
| `claim_*_batch` | a second vesting input with the same datum |
| `claim_*_typical` | a wallet input and a payout to a key |
| `claim_*_any_out` | one output at any address |

The same limits apply to every shape: continuations up to one more than the vesting inputs, up to two signatories, up to one withdrawal for a script beneficiary, any validity upper bound, and a single vested asset.
[`tx-shapes.md`](tx-shapes.md) has the details.

## Findings

The validator checks a continuation's payment credential but not its staking credential, so a claimant can redirect the staking rewards of the vested funds.
`chain_address_fixed` is stated for the payment credential only for this reason.

## Properties

[`properties.json`](properties.json) lists the properties and the theorems for each.
[`validator-metadata.json`](validator-metadata.json) records the upstream source snapshot.

Blaster theorems depend on Z3 through the `blasterProven` axiom; the `Robustness`, `Functionality` and `MultiTx` theorems use the standard Lean axioms only.