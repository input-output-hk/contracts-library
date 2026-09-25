//// Schedule helpers for the event-triggered assets substandard — the
//// tokenized bond's baked-value arithmetic (spec §3.5, §4.4, §4.5).
////
//// The schedule `[(d1,v1) … (d4,v4)]` is baked as validator constants,
//// precomputed off-chain in fixed-point `scale` units. There is no on-chain
//// compounding: the transformation is a pure time lookup
//// (`lookup(schedule, now)`) and the graduation mints exactly
//// `burned × v4 / scale` per owner. `v4`, `d4` and `d1` are derived from the
//// baked list, so every validator that carries the schedule derives the same
//// constants.
////
//// The payout is **per-owner**: whole holdings burn (§4.5), so each owner's
//// burned quantity is exact and their share is `floor(Q_owner × v4 / scale)`.
//// The total mint is the sum of the per-owner shares — rounding dust is
//// never minted, so nobody gains from batching. The minting logic's `Burn`
//// mode and the graduated asset's native policy call the same functions on
//// the same transaction, guaranteeing the two scripts agree on the amount.

use aiken/collection/list
use aiken/math.{max}
use aiken/option.{map, or_else}
use cardano/address.{Credential, Inline}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{Input, Output}
use event_triggered/types.{ScheduleStep}

/// The recorded value at `now` (§4.4): the value of the latest step whose
/// deadline is ≤ now. `None` before the first deadline (no step applies yet).
/// Deterministic even for an unsorted list — the latest applicable deadline
/// wins; deployments bake sorted schedules.
pub fn lookup(schedule: List<ScheduleStep>, now: Int) -> Option<Int> {
  schedule
    |> list.reduce(
        None,
        fn(acc: Option<(Int, Int)>, step: ScheduleStep) {
          let later = when acc is {
            Some((deadline, _)) -> step.deadline > deadline
            None -> True
          }
          if step.deadline <= now && later {
            Some((step.deadline, step.value))
          } else {
            acc
          }
        },
      )
    |> map(fn(step) { step.2nd })
}

/// The schedule's last deadline — `d4`. The graduation window opens here
/// (§4.5) and the schedule is exhausted afterwards (§5).
pub fn final_deadline(schedule: List<ScheduleStep>) -> Option<Int> {
  list.reduce(
    schedule,
    None,
    fn(acc: Option<Int>, step: ScheduleStep) {
      Some(max(or_else(acc, step.deadline), step.deadline))
    },
  )
}

/// The schedule's final value — `v4`, the value of the latest deadline
/// (§3.5: `v4 ≈ 1.1699 × scale`). The graduation math reads the baked `v4`,
/// never the reference datum's (possibly stale) recorded value.
pub fn final_value(schedule: List<ScheduleStep>) -> Option<Int> {
  schedule
    |> list.reduce(
        None,
        fn(acc: Option<(Int, Int)>, step: ScheduleStep) {
          let take = when acc is {
            Some((deadline, _)) -> step.deadline > deadline
            None -> True
          }
          if take {
            Some((step.deadline, step.value))
          } else {
            acc
          }
        },
      )
    |> map(fn(step) { step.2nd })
}

/// One owner's payout: `floor(Q × v4 / scale)` (§4.5).
pub fn payout(burned: Int, final_value: Int, scale: Int) -> Int {
  burned * final_value / scale
}

/// Group the burned principal holdings by owner (I5). Every input holding
/// the principal asset name contributes its **whole** holding, which makes
/// per-owner destination attribution exact. Fails closed (`None`) when a
/// holding input's stake credential is not inline — PLB UTxOs always stake
/// to their holder's inline credential, so anything else is unexpected.
pub fn burned_holdings(
  inputs: List<Input>,
  policy: PolicyId,
  principal_name: ByteArray,
) -> Option<List<(Credential, Int)>> {
  list.reduce(
    inputs,
    Some([]),
    fn(acc: Option<List<(Credential, Int)>>, input: Input) {
      when acc is {
        None -> None
        Some(holdings) -> {
          let quantity = quantity_of(input.output.value, policy, principal_name)
          if quantity > 0 {
            when owner_of(input.output) is {
              Some(owner) -> Some(add_to(holdings, owner, quantity))
              None -> None
            }
          } else {
            acc
          }
        }
      }
    },
  )
}

/// The scaled payout per owner, as `[(owner, share)]` in the same order.
pub fn scaled_payouts(
  holdings: List<(Credential, Int)>,
  final_value: Int,
  scale: Int,
) -> List<(Credential, Int)> {
  list.map(
    holdings,
    fn(entry) { (entry.1st, payout(entry.2nd, final_value, scale)) },
  )
}

/// The total mint the graduation must produce: the sum of the per-owner
/// shares. The graduated asset's native policy checks its mint against this
/// exact number — the same computation the minting logic's Burn mode runs.
pub fn total_payout(
  holdings: List<(Credential, Int)>,
  final_value: Int,
  scale: Int,
) -> Int {
  list.reduce(
    scaled_payouts(holdings, final_value, scale),
    0,
    fn(total: Int, entry: (Credential, Int)) { total + entry.2nd },
  )
}

/// The sum of the quantities in a `[(owner, quantity)]` list — the burned
/// total for holdings, the mint total for shares.
pub fn total(entries: List<(Credential, Int)>) -> Int {
  list.reduce(
    entries,
    0,
    fn(total: Int, entry: (Credential, Int)) { total + entry.2nd },
  )
}

// ----------------------------------------------------------------- helpers

/// An output's owner: its inline stake credential (§3.1). Pointer-backed or
/// absent stake credentials are not owners — they fail closed.
pub fn owner_of(output: Output) -> Option<Credential> {
  when output.address.stake_credential is {
    Some(Inline(cred)) -> Some(cred)
    _ -> None
  }
}

fn add_to(
  holdings: List<(Credential, Int)>,
  owner: Credential,
  quantity: Int,
) -> List<(Credential, Int)> {
  when holdings is {
    [] -> [(owner, quantity)]
    [head, ..tail] ->
      if head.1st == owner {
        [(owner, head.2nd + quantity), ..tail]
      } else {
        [head, ..add_to(tail, owner, quantity)]
      }
  }
}
