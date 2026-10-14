//// Coupon policy (native mint) for the event-triggered assets substandard —
//// one vault's `cNt` coupon tokens (spec §3.2, §4.5, §4.6, §4.7).
////
//// A coupon is a plain native asset whose **asset name is the decimal lovelace
//// amount** it is worth. This policy is outside the issuance dependency cone,
//// so it bakes the governed `cip_policy` directly and reads the spent
//// certificate's state from the transaction inputs.
////
//// Positive mints are admitted in exactly two shapes, each gated by the
//// transaction's own validity range (no oracle):
////   * a scheduled coupon for step `k` — exactly one unit of name
////     `encode(amounts[k])`, admitted when the validity range reaches
////     `start + k * interval` and the certificate advances `k-1 -> k`; or
////   * the graduation coupon — exactly one unit of name `encode(principal)`,
////     admitted at the final step, from `start + N * interval` on, when the
////     certificate is being retired (I5).
////
//// Negative mints (redemption burns) are always admitted; the vault ties the
//// payout to the burned value (I4).

use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{is_entirely_after}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{Input, Transaction}
use event_triggered/certificate
use event_triggered/schedule
use event_triggered/types.{CertificateDatum, CouponParams}

pub fn validate(
  self: Transaction,
  own_policy: PolicyId,
  params: CouponParams,
) -> Bool {
  let entries = dict.to_pairs(tokens(self.mint, own_policy))
  let positives = list.filter(entries, fn(entry) { entry.2nd > 0 })
  when positives is {
    [] -> !list.is_empty(entries)
    [Pair(name, 1)] -> validate_positive(self, name, params)
    // At most one positive name per mint.
    _ -> False
  }
}

/// A positive coupon mint is either the graduation coupon or a scheduled step
/// coupon, disambiguated by whether the transaction leaves a certificate
/// continuation.
fn validate_positive(self: Transaction, name, params: CouponParams) -> Bool {
  expect Some(amount) = schedule.decode_amount(name)
  let certs_in = certificate.cert_inputs(self.inputs, params.cip_policy)
  let certs_out = certificate.cert_outputs(self.outputs, params.cip_policy)
  when certs_out is {
    [] -> graduation(self, amount, certs_in, params)
    [(_, k_out, _)] -> scheduled(self, amount, k_out, certs_in, params)
    _ -> False
  }
}

/// The graduation coupon names exactly the baked `principal`, is admitted from
/// `start + N * interval` on, and is paired with a spent certificate at the
/// final step, burned with no continuation (I5).
fn graduation(
  self: Transaction,
  amount: Int,
  certs_in: List<(Input, Int, CertificateDatum)>,
  params: CouponParams,
) -> Bool {
  let final = schedule.final_step(params.amounts)
  and {
    amount == params.principal,
    when certs_in is {
      [(_, k, d)] -> and {
          k == final,
          is_entirely_after(
            self.validity_range,
            d.start + k * params.interval - 1,
          ),
          dict.to_pairs(tokens(self.mint, params.cip_policy)) == [
            Pair(schedule.step_name(k), -1),
          ],
        }
      _ -> False
    },
  }
}

/// A scheduled coupon: the certificate advances `k-1 -> k`, `now` reaches the
/// step's deadline, and the coupon names exactly `amounts[k]` (I3).
fn scheduled(
  self: Transaction,
  amount: Int,
  k_out: Int,
  certs_in: List<(Input, Int, CertificateDatum)>,
  params: CouponParams,
) -> Bool {
  when (certs_in, schedule.amount_at(params.amounts, k_out)) is {
    ([(_, k_in, d)], Some(expected)) -> and {
        k_out == k_in + 1,
        amount == expected,
        is_entirely_after(
          self.validity_range,
          d.start + k_out * params.interval - 1,
        ),
        dict.to_pairs(tokens(self.mint, params.cip_policy)) == [
          Pair(schedule.step_name(k_in), -1),
          Pair(schedule.step_name(k_out), 1),
        ],
      }
    _ -> False
  }
}
