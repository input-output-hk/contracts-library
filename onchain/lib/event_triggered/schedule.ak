//// Schedule and asset-name helpers for the event-triggered assets
//// substandard — the tokenized bond's baked constants (spec §3.2, §3.4,
//// §4.5, §4.7).
////
//// A certificate's **asset name is one byte: its current step** (`0` at
//// deposit, `N` at maturity). Coupons are plain native assets whose **asset
//// name is the decimal lovelace amount** they are worth. The per-vault coupon
//// policy bakes the `interval` and the `amounts`, so every validator that
//// carries them derives the same terms; the certificate's `cnt_policy` datum
//// selects which policy applies.

use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use aiken/primitive/int
use aiken/primitive/string
use cardano/assets.{AssetName, PolicyId, Value, tokens}

/// The certificate asset name for step `k`: exactly one byte, big-endian.
/// `N <= 255` is a deployment invariant.
pub fn step_name(k: Int) -> AssetName {
  bytearray.from_int_big_endian(k, 1)
}

/// Decode a certificate asset name: `Some(k)` iff the name is exactly one
/// byte. Any other name under the governed policy is not a certificate.
pub fn step_of_name(name: AssetName) -> Option<Int> {
  if bytearray.length(name) == 1 {
    Some(bytearray.to_int_big_endian(name))
  } else {
    None
  }
}

/// The `amount` of step `k` (1-indexed), or `None` if the step is out of
/// range.
pub fn amount_at(amounts: List<Int>, k: Int) -> Option<Int> {
  list.at(amounts, k - 1)
}

/// The certificate's final `step`: the number of coupon steps. A certificate
/// reaches it only by claiming every coupon in order (I7), and it is the only
/// step at which a retirement is admitted (§4.7).
pub fn final_step(amounts: List<Int>) -> Int {
  list.length(amounts)
}

/// Encode a lovelace amount as the coupon asset name: its decimal bytes
/// (§3.2). Name `"1124"` is worth `1124` lovelace.
pub fn encode_amount(amount: Int) -> AssetName {
  int.to_string(amount) |> string.to_bytearray
}

/// Decode a coupon asset name into its lovelace amount (§3.2). `None` when the
/// name is not canonical decimal — the round-trip check rejects leading zeros
/// (so `"01124"` cannot alias `"1124"`) and any non-digit byte.
pub fn decode_amount(name: AssetName) -> Option<Int> {
  when int.from_utf8(name) is {
    Some(amount) ->
      if encode_amount(amount) == name {
        Some(amount)
      } else {
        None
      }
    None -> None
  }
}

/// The lovelace value redeemed by the negative mints under `cnt_policy`:
/// `Σ decode(name) × |quantity|` over burned coupons (I4). `None` when any
/// burned name is not canonical decimal — the vault fails closed rather than
/// paying an undecodable coupon. Positive entries are ignored here; the coupon
/// policy validates those.
pub fn total_burned(mint: Value, cnt_policy: PolicyId) -> Option<Int> {
  dict.foldl(
    tokens(mint, cnt_policy),
    Some(0),
    fn(name: AssetName, quantity: Int, acc: Option<Int>) {
      when acc is {
        None -> None
        Some(total) ->
          if quantity < 0 {
            when decode_amount(name) is {
              Some(amount) -> Some(total + amount * ( 0 - quantity ))
              None -> None
            }
          } else {
            acc
          }
      }
    },
  )
}
