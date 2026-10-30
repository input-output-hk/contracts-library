//// Linear vesting — parameterized validation logic.
//// See `docs/vesting/spec.md`. This module holds the reusable
//// predicates; `validators/linear_vesting.ak` is a thin wrapper over them.

use aiken/collection/list
use aiken/interval.{Finite, is_entirely_after}
use aiken/primitive/bytearray
use authorization
use cardano/address.{Address}
use cardano/assets
use cardano/transaction.{Datum, InlineDatum, Input, Output, Transaction}
use vesting/types.{VestedAsset, VestingDatum}

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

  // The bundle must be well-formed: keys strictly ascending (so no asset is
  // listed twice) and every total non-negative. Checked on `Claim` only, so a
  // malformed instance can be recovered by the locker via `Cancel`.
  expect bundle_well_formed(datum.vesting)

  // §5.2 — read `now` as the finite lower bound of the validity range.
  expect Finite(now) = validity_range.lower_bound.bound_type

  // Only inline datums are accepted on the contract input.
  expect InlineDatum(_) = own_input.datum

  // I2/I3/I4 — every asset's required remainder stays in continuing outputs that
  // reproduce the input's full address and datum, one per contract input
  // sharing both (anti double-satisfaction and anti-merge, without input-count
  // limits). Continuations carry no extra tokens and no reference script.
  remainders_preserved(datum, own_input, inputs, outputs, now)
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

  // §5.2 — `now` is the finite lower bound; require it to be strictly after
  // recovery, so the real inclusion time is guaranteed past `recovery_time`.
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

/// A vesting bundle is well-formed when its `(policy, name)` keys are strictly
/// ascending (byte-wise, policy first) and every `total` is non-negative.
/// Strict ordering rules out duplicate assets, which would otherwise each be
/// checked on their own and protect only one copy. See spec §3.1.
pub fn bundle_well_formed(vesting: List<VestedAsset>) -> Bool {
  when vesting is {
    [] -> True
    [a] -> a.total >= 0
    [a, b, ..rest] ->
      a.total >= 0 && key_less_than(a, b) && bundle_well_formed([b, ..rest])
  }
}

/// Strict byte-wise order on `(policy, name)`.
fn key_less_than(a: VestedAsset, b: VestedAsset) -> Bool {
  when bytearray.compare(a.policy, b.policy) is {
    Less -> True
    Equal -> bytearray.compare(a.name, b.name) == Less
    Greater -> False
  }
}

/// Is `output` at exactly `address` (payment *and* stake credential) and
/// carrying exactly `datum_data`?
fn same_instance(output: Output, address: Address, datum_data: Datum) -> Bool {
  output.address == address && output.datum == datum_data
}

/// Number of inputs at `address` carrying datum `datum_data`.
fn shared_input_count(
  inputs: List<Input>,
  address: Address,
  datum_data: Datum,
) -> Int {
  list.count(
    inputs,
    fn(input) { same_instance(input.output, address, datum_data) },
  )
}

/// A continuation holds only ada and the assets listed in the bundle, and no
/// reference script. Nothing else can be pushed onto the contract's UTxO.
fn is_clean(output: Output, vesting: List<VestedAsset>) -> Bool {
  output.reference_script == None && list.all(
    assets.flatten(output.value),
    fn(entry) {
      let (policy, name, _) = entry
      policy == assets.ada_policy_id || list.any(
        vesting,
        fn(asset) { asset.policy == policy && asset.name == name },
      )
    },
  )
}

/// Enforce, for the instance being spent, that its schedule-bearing value stays
/// locked in continuing outputs — those at the spent input's *full* address
/// (payment and stake credential) carrying the *same* (inline) datum. Every
/// continuation must also be clean: only ada and listed assets, no reference
/// script.
///
/// **Instance-count preservation (spec §5.1).** Each continuation must
/// *independently* hold the full per-asset remainder, and there must be at least
/// `k` of them, where `k` is the number of inputs sharing this address and datum.
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
  now: Int,
) -> Bool {
  let k = shared_input_count(inputs, own_input.address, own_input.datum)

  // Continuing outputs for this instance: same full address (so the stake
  // credential cannot be changed) and a datum equal to the spent input's (so
  // inline, reproduced verbatim).
  let continuations = list.filter(
    outputs,
    fn(output) { same_instance(output, own_input.address, own_input.datum) },
  )

  // Each continuation must, on its own, be clean and hold `required` of every
  // vested asset.
  let holds_full_remainder = fn(output: Output) {
    is_clean(output, datum.vesting) && list.all(
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
