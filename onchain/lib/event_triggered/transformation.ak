//// Transformation script (withdraw-0) — the scheduled transformation's time
//// gate (spec §4.4, T3).
////
//// The reference token (CIP-68 `222`) is custodied at the Programmable Logic
//// Base with this script as its inline stake credential. When it is spent on
//// the transfer path, `authorised_stake_cred` is this script credential and
//// the core `transfer` validator requires this withdraw-0 — which validates
//// the in-place datum change: holder-passive and permissionless, no
//// signatures, anyone may submit (normally the issuer; the holder can force
//// it).
////
//// The update is a **pure time lookup of the baked constants** (I4): the
//// output datum must keep the input's `metadata` and `version`, mirror the
//// baked schedule, and record `lookup(schedule, now)` — so a late submission
//// (`now ≥ d_{k+1}`) simply lands on the current step; staleness costs
//// nothing (§5). The gate is `d1 ≤ now < d4`: before `d1` no step applies
//// yet, and after `d4` the schedule is exhausted — the script rejects any
//// further update and the value stops (the graduation window opens at `d4`,
//// §4.5; the graduation math reads the baked `v4`, not this datum).
////
//// The principal tokens never move — only the instrument's recorded value
//// changes (I4). The paired continuation is a transfer-path spend: address
//// and value preservation are the core's business; here the reference token
//// itself is pinned to its continuation. The third-party path cannot do
//// any of this — it preserves datums byte-for-byte and is graduation-only
//// in this instrument.

use aiken/collection/list
use aiken/interval.{Finite, IntervalBound}
use cardano/address.{Credential, Inline}
use cardano/assets.{quantity_of}
use cardano/transaction.{InlineDatum, Output, Transaction}
use event_triggered/schedule
use event_triggered/types.{ReferenceDatum, TransformationParams}

/// Validate the scheduled transformation: exactly one UTxO staked to this
/// script — the reference token — is rewritten in place on the transfer
/// path, its recorded value stepping to the current schedule step. (The
/// withdraw-0's redeemer is an authorization signal; this predicate does not
/// read it.)
pub fn validate(
  account: Credential,
  self: Transaction,
  params: TransformationParams,
) -> Bool {
  // Exactly one UTxO is staked to this script: the reference token (§3.3).
  // A bare withdrawal that spends nothing of ours fails here, so this
  // withdraw-0 cannot be run vacuously.
  expect [spent] = list.filter(
    self.inputs,
    fn(input) { input.output.address.stake_credential == Some(Inline(account)) },
  )
  expect
    quantity_of(spent.output.value, params.own_policy, params.reference_name) == 1
  // The paired continuation keeps the token in place (address and value
  // preservation are the core's; the reference unit is pinned here).
  expect [continuation] = list.filter(
    self.outputs,
    fn(output: Output) {
      quantity_of(output.value, params.own_policy, params.reference_name) == 1
    },
  )
  expect Some(now) = lower_bound(self)
  expect Some(final) = schedule.final_deadline(params.schedule)
  and {
    continuation.address == spent.output.address,
    // §5: after `d4` the schedule is exhausted (the final v4 write is admitted
    // at exactly d4). Before `d1` no step applies — `pure_lookup` rejects the
    // `None` lookup.
    now <= final,
    // The datum change is a pure time lookup of the baked constants (I4).
    pure_lookup(spent.output, continuation, now, params),
  }
}

/// The output datum keeps `metadata` and `version`, always mirrors the baked
/// schedule (on both sides — the schedule is never rewritten), and records
/// `lookup(schedule, now)` as the current value.
fn pure_lookup(
  spent: Output,
  continuation: Output,
  now: Int,
  params: TransformationParams,
) -> Bool {
  when spent.datum is {
    InlineDatum(data) -> {
      expect before: ReferenceDatum = data
      when continuation.datum is {
        InlineDatum(data) -> {
          expect after: ReferenceDatum = data
          and {
            after.metadata == before.metadata,
            after.version == before.version,
            before.extra.schedule == params.schedule,
            after.extra.schedule == params.schedule,
            when schedule.lookup(params.schedule, now) is {
              Some(value) -> after.extra.value == value
              None -> False
            },
          }
        }
        _ -> False
      }
    }
    _ -> False
  }
}

/// The transaction's `now`: the validity range's lower bound, normalized to
/// an inclusive bound (an exclusive bound `t` means the real slot is ≥ t+1).
/// `None` when the lower bound is not finite — the transformation's time
/// gate requires a finite lower bound and fails closed.
fn lower_bound(self: Transaction) -> Option<Int> {
  when self.validity_range.lower_bound is {
    IntervalBound { bound_type: Finite(t), is_inclusive: True } -> Some(t)
    IntervalBound { bound_type: Finite(t), is_inclusive: False } -> Some(t + 1)
    _ -> None
  }
}
