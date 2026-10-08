//// Coupon policy (native mint) for the event-triggered assets substandard —
//// the `cNt` coupon tokens (spec §3.2, §4.4, §4.6).
////
//// A coupon is a plain native asset whose **asset name is the decimal lovelace
//// amount** it is worth. This policy is outside the issuance dependency cone,
//// so it bakes the governed `cip_policy` directly and reads the spent
//// certificate's `step` anchor from the transaction inputs.
////
//// Positive mints are admitted in exactly two shapes, each gated by the
//// transaction's own validity range (no oracle):
////   * a scheduled coupon for step `k` — exactly one unit of name `amount_k`,
////     admitted when `now ≥ d_k`, the spent certificate records `step: k-1` and
////     the continuation records `step: k` (I3); or
////   * the graduation coupon — exactly one unit of name `principal`, admitted
////     when `now ≥ d4`, the spent certificate is at its final step and is
////     being retired (I5).
////
//// Negative mints (redemption burns) are always admitted; the vault ties the
//// payout to the burned value (I4).

use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{is_entirely_after}
use cardano/assets.{AssetName, PolicyId, tokens}
use cardano/transaction.{Input, Output, Transaction}
use event_triggered/certificate
use event_triggered/schedule
use event_triggered/types.{CouponParams, ScheduleStep}

pub fn validate(
  self: Transaction,
  own_policy: PolicyId,
  params: CouponParams,
) -> Bool {
  let entries = tokens(self.mint, own_policy) |> dict.to_pairs()
  let positives = list.filter(entries, fn(entry) { entry.2nd > 0 })
  when positives is {
    [] -> !list.is_empty(entries)
    [Pair(name, quantity)] -> and {
        quantity == 1,
        validate_positive(self, name, params),
      }
    // At most one positive name per mint.
    _ -> False
  }
}

/// A positive coupon mint is either the graduation coupon or a scheduled step
/// coupon, disambiguated by whether the transaction retires a certificate.
fn validate_positive(
  self: Transaction,
  name: AssetName,
  params: CouponParams,
) -> Bool {
  when schedule.decode_amount(name) is {
    None -> False
    Some(amount) ->
      if is_retirement(self, params) {
        graduation(self, amount, params)
      } else {
        scheduled(self, amount, params)
      }
  }
}

/// Is a certificate being retired in this transaction? A negative `cip_policy`
/// mint is the retirement shape (§4.6).
fn is_retirement(self: Transaction, params: CouponParams) -> Bool {
  tokens(self.mint, params.cip_policy)
    |> dict.values
    |> list.any(fn(quantity) { quantity < 0 })
}

/// The graduation coupon names exactly the baked `principal`, is admitted from
/// `d4` on, and is paired with a spent certificate at its final step and no
/// continuation (I5).
fn graduation(self: Transaction, amount: Int, params: CouponParams) -> Bool {
  expect Some(d4) = schedule.final_deadline(params.schedule)
  let final_step = schedule.final_step(params.schedule)
  let inputs = certificate.cert_inputs(
    self.inputs,
    params.cip_policy,
    params.certificate_name,
  )
  let outputs = certificate.cert_outputs(
    self.outputs,
    params.cip_policy,
    params.certificate_name,
  )
  and {
    amount == params.principal,
    is_entirely_after(self.validity_range, d4 - 1),
    when inputs is {
      [input] -> certificate.step_of(input.output) == Some(final_step)
      _ -> False
    },
    list.is_empty(outputs),
  }
}

/// A scheduled coupon: some step `k` whose amount equals the coupon name, with
/// `now ≥ d_k`, the spent certificate at `step: k-1`, and the continuation
/// advanced to `step: k` — the only advance that also binds the mint to the
/// anchor, so no step can be claimed twice (I3).
fn scheduled(self: Transaction, amount: Int, params: CouponParams) -> Bool {
  let inputs = certificate.cert_inputs(
    self.inputs,
    params.cip_policy,
    params.certificate_name,
  )
  let outputs = certificate.cert_outputs(
    self.outputs,
    params.cip_policy,
    params.certificate_name,
  )
  any_step(params.schedule, 1, self, amount, inputs, outputs)
}

/// Walk the schedule with its 1-based step index, admitting iff some step's
/// amount equals the coupon and its anchor/deadline gates hold.
fn any_step(
  schedule: List<ScheduleStep>,
  k: Int,
  self: Transaction,
  amount: Int,
  inputs: List<Input>,
  outputs: List<Output>,
) -> Bool {
  when schedule is {
    [] -> False
    [step, ..rest] -> or {
        and {
          step.amount == amount,
          is_entirely_after(self.validity_range, step.deadline - 1),
          when inputs is {
            [input] -> certificate.step_of(input.output) == Some(k - 1)
            _ -> False
          },
          when outputs is {
            [output] -> certificate.step_of(output) == Some(k)
            _ -> False
          },
        },
        any_step(rest, k + 1, self, amount, inputs, outputs),
      }
  }
}
