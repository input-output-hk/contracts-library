//// Linear vesting — parameterized validation logic.
//// See `specs/vesting/linear-vesting.md`. This module holds the reusable
//// predicates; `validators/linear_vesting.ak` is a thin wrapper over them.

use aiken/collection/list
use aiken/interval.{Finite, is_entirely_after}
use authorization
use cardano/address.{Credential}
use cardano/assets
use cardano/transaction.{Datum, InlineDatum, Input, Output, Transaction}
use vesting/types.{VestingDatum}

/// Full validation of a `Claim`. `own_input` is the contract UTxO being spent
/// (its address gives this script's payment credential).
pub fn validate_claim(
  datum: VestingDatum,
  own_input: Output,
  tx: Transaction,
) -> Bool {
  let  
      Transaction {
        inputs,
        outputs,
        validity_range,
        extra_signatories,
        withdrawals,
        ..
      }
    = tx

  // I1 — the beneficiary credential must be satisfied.
  expect
    authorization.is_authorized(
      datum.beneficiary,
      extra_signatories,
      withdrawals,
    )

  // The schedule must be well-formed. The datum is untrusted input, so we
  // re-check rather than assume the locker behaved.
  expect datum.start_time < datum.end_time

  // §5.2 — read `now` as the finite lower bound of the validity range.
  expect Finite(now) = validity_range.lower_bound.bound_type

  // Only inline datums are accepted on the contract input.
  expect InlineDatum(_) = own_input.datum
  let own_credential = own_input.address.payment_credential

  // I2/I3/I4 — every asset's required remainder stays in continuing outputs that
  // reproduce the datum verbatim, one per contract input sharing this datum
  // (anti double-satisfaction and anti-merge, without input-count limits).
  remainders_preserved(datum, own_input, inputs, outputs, own_credential, now)
}

/// Full validation of a `Cancel`. After `recovery_time` the `locker` may
/// recover whatever remains; no continuing output is required. See spec §4.3.
pub fn validate_cancel(datum: VestingDatum, tx: Transaction) -> Bool {
  let Transaction { validity_range, extra_signatories, withdrawals, .. } = tx

  // The locker credential must be satisfied.
  expect
    authorization.is_authorized(datum.locker, extra_signatories, withdrawals)

  // Schedule sanity: recovery is always strictly after the end of vesting, so a
  // malicious locker cannot set it early and recover unvested funds.
  expect datum.start_time < datum.end_time
  expect datum.end_time < datum.recovery_time

  // §5.2 — `now` is the finite lower bound; require it to be at/after recovery,
  // so the real inclusion time is guaranteed past `recovery_time`.
  is_entirely_after(validity_range, datum.recovery_time)
}

/// Quantity of an asset that has vested by `now`, given its original `total`
/// and the schedule `[start, end]`. Floored, so it never over-releases, and
/// non-decreasing in `now`. See spec §3.3.
///
/// Caller guarantees `start < end`.
pub fn vested_quantity(total: Int, start: Int, end: Int, now: Int) -> Int {
  if now <= start {
    0
  } else if now >= end {
    total
  } else {
    total * ( now - start ) / ( end - start )
  }
}

/// Number of inputs locked by `credential` carrying datum `datum_data`.
fn shared_input_count(
  inputs: List<Input>,
  credential: Credential,
  datum_data: Datum,
) -> Int {
  list.count(
    inputs,
    fn(input) {
      input.output.address.payment_credential == credential && input.output.datum == datum_data
    },
  )
}

/// Enforce, for the instance being spent, that its schedule-bearing value stays
/// locked in continuing outputs — those at this script's payment credential
/// carrying the *same* (inline) datum.
///
/// **Instance-count preservation (spec §5.1).** Each continuation must
/// *independently* hold the full per-asset remainder, and there must be at least
/// `k` of them, where `k` is the number of contract inputs sharing this datum.
/// Requiring `k` *separate* continuations (rather than only an aggregate
/// `k × required`) forbids collapsing several instances into a single UTxO: a
/// merge would drop `k` to 1 on a later spend and let the remainder that belonged
/// to the other instances be swept as unprotected surplus. Keeping the count
/// pinned means `k` can never shrink below the number of live instances.
fn remainders_preserved(
  datum: VestingDatum,
  own_input: Output,
  inputs: List<Input>,
  outputs: List<Output>,
  own_credential: Credential,
  now: Int,
) -> Bool {
  let k = shared_input_count(inputs, own_credential, own_input.datum)

  // Continuing outputs for this instance: same script credential, datum
  // byte-identical to the spent input's (so inline, reproduced verbatim).
  let continuations = list.filter(
    outputs,
    fn(output) {
      output.address.payment_credential == own_credential && output.datum == own_input.datum
    },
  )

  // Each continuation must, on its own, hold `required` of every vested asset.
  let holds_full_remainder = fn(output: Output) {
    list.all(
      datum.vesting,
      fn(asset) {
        let required = asset.total - vested_quantity(
          asset.total,
          datum.start_time,
          datum.end_time,
          now,
        )
        assets.quantity_of(output.value, asset.policy, asset.name) >= required
      },
    )
  }

  // Spec §8.2 — at or after `end_time` every asset has fully vested (required = 0
  // for all), so no continuation is required and the whole bundle may be taken
  // (full claim, I4). Strictly before `end_time`, require `k` separate
  // continuations that each hold the full remainder.
  if now >= datum.end_time {
    True
  } else {
    list.length(continuations) >= k && list.all(
      continuations,
      holds_full_remainder,
    )
  }
}
