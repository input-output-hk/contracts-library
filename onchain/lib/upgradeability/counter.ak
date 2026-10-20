use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Address, Credential}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Spend, Transaction, find_input,
}

/// State of the demo counter used to exercise the upgradeability pattern end to
/// end.
///
/// - `count` is the counter value.
/// - `owner` gates the opt-in `Upgrade` path (per-UTxO consent).
///
/// The demo assumes at most one counter UTxO per script address and one
/// continuation per target address per transaction. A production protocol
/// would tag continuations (e.g. a `prev_input` datum field or a per-UTxO NFT)
/// to support batching; that is orthogonal to the upgradeability mechanics this
/// demo exercises.
pub type CounterDatum {
  count: Int,
  owner: Credential,
}

/// Actions accepted by the counter demo.
///
/// `Tick` is the ordinary counter step, accepted by the forced logic and by
/// both opt-in versions. `Upgrade` is the dedicated migration path, accepted
/// only by the opt-in V1 validator.
pub type CounterRedeemer {
  Tick
  Upgrade
}

/// The first output at `target_address`, if any.
fn find_continuation(
  self: Transaction,
  target_address: Address,
) -> Option<Output> {
  list.find(self.outputs, fn(out) { out.address == target_address })
}

/// Validate a forced counter tick: the input referenced by `own_ref` must be
/// settled by a continuation at its own address that increments `count` by one,
/// preserves `owner`, and does not decrease the lovelace held.
pub fn validate_counter_tick(
  self: Transaction,
  own_ref: OutputReference,
) -> Bool {
  expect Some(input) = find_input(self.inputs, own_ref)
  expect InlineDatum(in_raw) = input.output.datum
  expect CounterDatum { count, owner } = in_raw

  when find_continuation(self, input.output.address) is {
    Some(out) -> {
      expect InlineDatum(out_raw) = out.datum
      expect CounterDatum { count: out_count, owner: out_owner } = out_raw
      and {
        out_count == count + 1,
        out_owner == owner,
        assets.lovelace_of(out.value) >= assets.lovelace_of(input.output.value),
      }
    }
    None -> False
  }
}

/// Validate an opt-in migration of the input referenced by `own_ref`: the same
/// state must reappear at `v2_address`, with `count` and `owner` preserved and
/// no decrease in lovelace.
pub fn validate_counter_migrate(
  self: Transaction,
  own_ref: OutputReference,
  v2_address: Address,
) -> Bool {
  expect Some(input) = find_input(self.inputs, own_ref)
  expect InlineDatum(in_raw) = input.output.datum
  expect CounterDatum { count, owner } = in_raw

  when find_continuation(self, v2_address) is {
    Some(out) -> {
      expect InlineDatum(out_raw) = out.datum
      expect CounterDatum { count: out_count, owner: out_owner } = out_raw
      and {
        out_count == count,
        out_owner == owner,
        assets.lovelace_of(out.value) >= assets.lovelace_of(input.output.value),
      }
    }
    None -> False
  }
}

/// Whether the input referenced by `ref` was spent with the `Upgrade` action.
///
/// A migration script uses this to bind a forwarded V1 input to the upgrade
/// path, so a V1 UTxO cannot be migrated while being spent under a normal
/// action.
pub fn spent_with_upgrade(self: Transaction, ref: OutputReference) -> Bool {
  let upgrade: Data = Upgrade
  when pairs.get_first(self.redeemers, Spend(ref)) is {
    Some(redeemer) -> redeemer == upgrade
    None -> False
  }
}
