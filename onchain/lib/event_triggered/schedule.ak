//// Schedule and coupon-name helpers for the event-triggered assets
//// substandard — the tokenized bond's baked constants (spec §3.4, §4.4, §4.6).
////
//// The deployment-supplied schedule `[(d1,a1) … (dn,an)]` is baked as
//// validator constants. There is no on-chain oracle or compounding: each step
//// gates the claim of one coupon whose **asset name is the decimal lovelace
//// amount** it is worth. The last deadline, the final step and every step's
//// amount are derived from the baked list, so every validator that carries
//// the schedule derives the same constants.

use aiken/collection/dict
use aiken/collection/list
use aiken/math.{max}
use aiken/option.{or_else}
use aiken/primitive/int
use aiken/primitive/string
use cardano/assets.{AssetName, PolicyId, Value, tokens}
use event_triggered/types.{ScheduleStep}

/// The schedule's last deadline — `d4`. The graduation window opens here
/// (§4.6).
pub fn final_deadline(schedule: List<ScheduleStep>) -> Option<Int> {
  list.reduce(
    schedule,
    None,
    fn(acc: Option<Int>, step: ScheduleStep) {
      Some(max(or_else(acc, step.deadline), step.deadline))
    },
  )
}

/// The certificate's final `step`: the number of schedule steps. A certificate
/// reaches it only by claiming every coupon in order (I7), and it is the only
/// step at which a retirement is admitted (§4.6).
pub fn final_step(schedule: List<ScheduleStep>) -> Int {
  list.length(schedule)
}

/// The `amount` of step `k` (1-indexed), or `None` if the step is out of range.
pub fn amount_at(schedule: List<ScheduleStep>, k: Int) -> Option<Int> {
  when list.at(schedule, k - 1) is {
    Some(step) -> Some(step.amount)
    None -> None
  }
}

/// The `deadline` of step `k` (1-indexed), or `None` if out of range.
pub fn deadline_at(schedule: List<ScheduleStep>, k: Int) -> Option<Int> {
  when list.at(schedule, k - 1) is {
    Some(step) -> Some(step.deadline)
    None -> None
  }
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
