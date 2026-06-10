//// Reusable linear-vesting validation logic.
////
//// Faithful port of Anastasia Labs' `linear-vesting`. The release schedule is
//// installment-based: the vesting window is split into `total_installments`
//// equal time slices, and at any moment the amount that *must remain* locked is
////
//// ```
//// expected_remaining = ceil(future_installments * total_vesting_qty / total_installments)
//// ```
////
//// where `future_installments` is the number of (rounded-up) installments still
//// ahead. A large `total_installments` approximates a continuous linear release.

use aiken/collection/list
use aiken/interval.{Finite}
use cardano/address.{Script, VerificationKey}
use cardano/assets
use cardano/transaction.{InlineDatum, Input, OutputReference, Transaction,
  ValidityRange}
use vesting/types.{VestingDatum}

/// Validate a partial unlock: the beneficiary withdraws the vested portion and
/// returns the remainder to the script with an unchanged datum.
pub fn partial_unlock(
  datum: VestingDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let own_output = transaction.resolve_input(self.inputs, own_ref)
  let own_address = own_output.address
  expect Script(own_hash) = own_address.payment_credential

  // Exactly one output must return to the script address (also errors if none).
  expect [continuing] =
    list.filter(self.outputs, fn(output) { output.address == own_address })

  let now = lower_inclusive(self.validity_range)

  let old_remaining =
    assets.quantity_of(
      own_output.value,
      datum.vesting_asset.policy_id,
      datum.vesting_asset.asset_name,
    )
  let new_remaining =
    assets.quantity_of(
      continuing.value,
      datum.vesting_asset.policy_id,
      datum.vesting_asset.asset_name,
    )

  let vesting_period_length = datum.vesting_period_end - datum.vesting_period_start
  let vesting_time_remaining = datum.vesting_period_end - now
  let time_between_installments =
    div_ceil(vesting_period_length, datum.total_installments)
  let future_installments =
    div_ceil(vesting_time_remaining, time_between_installments)
  let expected_remaining =
    div_ceil(
      future_installments * datum.total_vesting_qty,
      datum.total_installments,
    )

  expect VerificationKey(beneficiary_hash) =
    datum.beneficiary.payment_credential

  expect InlineDatum(continuing_data) = continuing.datum
  expect continuing_datum: VestingDatum = continuing_data

  and {
    // Authorised by the beneficiary's signature.
    list.has(self.extra_signatories, beneficiary_hash)?,
    // Unlocking has started.
    (datum.first_unlock_possible_after < now)?,
    // A partial unlock must leave a positive, strictly smaller remainder.
    (0 < new_remaining)?,
    (new_remaining < old_remaining)?,
    // Exactly the scheduled amount is left behind.
    (expected_remaining == new_remaining)?,
    // The arrangement (datum) is preserved.
    (continuing_datum == datum)?,
    // Anti-double-satisfaction: only one script input in the transaction.
    (count_script_inputs(self.inputs, own_hash) == 1)?,
  }
}

/// Validate a full unlock: after the vesting period ends, the beneficiary may
/// withdraw the entire remaining balance.
pub fn full_unlock(datum: VestingDatum, self: Transaction) -> Bool {
  let now = lower_inclusive(self.validity_range)
  expect VerificationKey(beneficiary_hash) =
    datum.beneficiary.payment_credential

  and {
    list.has(self.extra_signatories, beneficiary_hash)?,
    (datum.vesting_period_end < now)?,
  }
}

// ## Helpers

/// Ceiling integer division: `ceil(x / y)`. Matches the reference
/// implementation's `pdivCeil` (relies on floor division, as in Plutus).
pub fn div_ceil(x: Int, y: Int) -> Int {
  1 + ( x - 1 ) / y
}

/// The earliest POSIX time the transaction can be on-chain, i.e. the inclusive
/// lower bound of its validity range. Fails if the lower bound is not finite.
fn lower_inclusive(range: ValidityRange) -> Int {
  when range.lower_bound.bound_type is {
    Finite(t) ->
      if range.lower_bound.is_inclusive {
        t
      } else {
        t + 1
      }
    _ -> fail @"validity range must have a finite lower bound"
  }
}

/// Count inputs guarded by the given script hash.
fn count_script_inputs(inputs: List<Input>, own_hash: ByteArray) -> Int {
  list.count(
    inputs,
    fn(input) {
      when input.output.address.payment_credential is {
        Script(hash) -> hash == own_hash
        VerificationKey(_) -> False
      }
    },
  )
}


fn vest(n: Int) {
  spend(
    datum: Option<VestingDatum>,
    redeemer: VestingRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(vesting_datum) = datum
    expect n > 3
    when redeemer is {
      PartialUnlock -> validation.partial_unlock(vesting_datum, own_ref, self)
      FullUnlock -> validation.full_unlock(vesting_datum, self)
    }
  }
}



