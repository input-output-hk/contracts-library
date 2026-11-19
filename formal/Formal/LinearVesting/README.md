# Linear vesting proofs

The Milestone 1.2 proofs target the linear-vesting spending validator from
commit `d629dce7`, with script hash
`95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a`.
The [validator metadata](validator-metadata.json) records the source revision
and compiled bytes. [Vesting specification](../../../docs/vesting/spec.md)

## Approach

`Spec.lean` defines `specAccepts d r ctx` to decide whether the model accepts a
transaction.
The proofs have three parts.

1. **Agreement** (Blaster, bounded): the compiled validator accepts exactly what the spec accepts, on the transaction shapes in `TxBuilder.lean`.
   Each direction is separate: `Sound` (validator accepts ⇒ spec accepts) and `Complete` (spec accepts ⇒ validator accepts).
2. **Spec properties** (plain Lean, unbounded): safety, acceptance, and chains of claims, proved about `specAccepts` for every transaction.
3. **Corollaries and tests**: spec properties carried to the validator through agreement, and fixed transactions run through both.

To carry a rejection result to an updated validator, prove `Sound` for its
compiled bytes under the corresponding hypotheses. Acceptance results require
the corresponding completeness proof.

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
| `Corollaries` | spec properties carried to `spendValidator` | Lean and Blaster |
| `Tests` | transaction examples for the spec and validator | Blaster |

## Transaction shapes

Each row identifies a pair of soundness and completeness theorems.
All five Claim shapes vest exactly one asset. The theorem statements and
constructors specify the validity range and the remaining context fields.

| Theorem pair | Inputs and outputs | List bounds |
| --- | --- | --- |
| `cancel_sound`, `cancel_complete` | Vesting input followed by arbitrary inputs, with arbitrary outputs | At most two signatories for a key locker, or at most two withdrawals for a script locker |
| `claim_sound`, `claim_complete` | Key beneficiary, one vesting input and up to two continuations | At most two signatories |
| `claim_sound_script`, `claim_complete_script` | Script beneficiary, one vesting input and up to two continuations | At most one withdrawal |
| `claim_sound_batch`, `claim_complete_batch` | Key beneficiary, two vesting inputs sharing a datum and up to three continuations | At most two signatories |
| `claim_sound_typical`, `claim_complete_typical` | Key beneficiary, one vesting input, one wallet input, a key payout and up to two continuations | At most two signatories |
| `claim_sound_any_out`, `claim_complete_any_out` | Key beneficiary, one vesting input and one output at an arbitrary address | At most two signatories |

See [Claim soundness](ClaimSound.lean), [Claim completeness](ClaimComplete.lean),
[Cancel soundness](CancelSound.lean), [Cancel completeness](CancelComplete.lean),
and [the transaction constructors](TxBuilder.lean).

## Address matching in the frozen snapshot

The frozen validator groups continuations by payment credential and datum.
`MultiTx.chain_address_fixed` therefore states equality of payment credentials
along a linked chain of claims accepted by the model. IO later changed the
validator to require the full address and datum. The hash above identifies the
artifact covered by this proof suite. [Frozen code](../../../onchain/lib/vesting/linear.ak#L124-L132) · [Chain theorem](MultiTx.lean#L163-L166) · [Upstream fix](https://github.com/input-output-hk/contracts-library/pull/72)

## Properties

[`properties.json`](properties.json) lists the active properties and their
theorem references. The model theorems describe `specAccepts`. The bridge to
compiled-validator behavior is the applicable agreement theorem with its
transaction-shape hypotheses. Concrete checks in `Tests.lean` exercise the
specified inputs.

The Blaster proofs trust Z3 through `Blaster.Tactic.blasterProven`.
The `Robustness`, `Functionality` and `MultiTx` modules use standard Lean axioms.
The chain results assume each step spends a continuation from the previous
step and that the model accepts each step. [Chain definition](MultiTx.lean#L105-L123)

### Earlier proof target and property IDs

The four earlier modules live under `Formal.LinearVesting.Old`. After
generating the same vesting fixture, run this command from `formal/` to check
all four through the dependencies of the final module.

```sh
lake build +Formal.LinearVesting.Old.Robustness
```

A successful run ends with `Build completed successfully`. The table maps the
earlier draft’s IDs to related entries in the current catalogue. Apply the
statement and hypotheses of each cited theorem when comparing coverage.
[Earlier property list at `2fbe7ac`](https://github.com/no-witness-labs/contracts-library/blob/2fbe7ac4c4ed8821aa4a03966ac0a949bc25ecf1/formal/Formal/LinearVesting/properties.json)

| Earlier ID | Earlier property | Related current IDs |
| --- | --- | --- |
| LV-001 to LV-004 | Arithmetic | LV-001 to LV-004 |
| LV-005 | Key-authorized partial claim | LV-006, LV-018 |
| LV-006 | Script-authorized partial claim | LV-006, LV-018 |
| LV-007 | Two funded continuations | LV-006, LV-013, LV-018 |
| LV-008 | Full claim | LV-019 |
| LV-009 | Authorized cancellation | LV-020 |
| LV-010 | Partial claims preserve datum and remainder | LV-010, LV-011 |
| LV-011 | Accepted cancellation occurs after recovery | LV-016 |
| LV-012 | Unauthorized key claim rejected | LV-009 |
| LV-013 | Underfunded continuation rejected | LV-010 |
| LV-014 | Changed datum rejected | LV-011 |
| LV-015 | Hashed input datum rejected | LV-012 |
| LV-016 | Script claim without a withdrawal rejected | LV-009 |
| LV-017 | Premature cancellation rejected | LV-016 |
| LV-018 | Unauthorized cancellation rejected | LV-015 |
| LV-019 | One continuation for two inputs rejected | LV-013 |
| LV-020 | Merged continuation rejected | LV-013 |
| LV-021 | Underfunded batch rejected | LV-013 |

## Reproduce the cancellation boundary

Use a checkout of the M1.2 branch that contains the frozen validator above.
Follow the [toolchain setup](../../README.md#build), including Aiken
`v1.1.22+39d6b04`, Lean 4.24.0 and Z3 4.15.2.

1. Run the positive and expected-rejection Aiken tests from `onchain/`.

   ```sh
   aiken check --seed 20261119 --match-tests 'vesting/linear.{cancel_after_recovery_ok,rejects_cancel_before_recovery}'
   ```

   Both tests should pass. The second passes when the validator rejects the
   premature cancellation. [Aiken test fixtures](../../../onchain/lib/vesting/linear.test.ak#L378-L388)

2. Generate the fixture and build the Lean examples from `formal/`.

   ```sh
   just flats
   lake build +Formal.LinearVesting.Tests
   ```

   `just flats` writes `Scripts/linear_vesting_spend.flat`. Lake should report
   a successful build. The Build guide explains which checkout supplies the
   Aiken source.

3. Inspect the compiled-validator results from `formal/`.

   ```sh
   lake env lean --stdin <<'LEAN'
   import Formal.LinearVesting.Tests
   #check Formal.LinearVesting.Tests.validator_accept_cancel
   #check Formal.LinearVesting.Tests.validator_reject_cancel_at_recovery
   #print axioms Formal.LinearVesting.Tests.validator_accept_cancel
   #print axioms Formal.LinearVesting.Tests.validator_reject_cancel_at_recovery
   LEAN
   ```

   Lean reports `validatorAccepts` for the authorized cancellation at 3001 ms
   and `validatorRejects` for the same locker at the inclusive boundary of
   3000 ms. Both results list `Blaster.Tactic.blasterProven` among their
   axioms. The test suite also checks an exclusive lower endpoint at the same
   recovery time. [Lean test fixtures](Tests.lean#L329-L355)
