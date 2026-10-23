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
/// - `prev_input` binds a continuation output to the UTxO it continues (`None`
///   only at the genesis lock). Every validation matches its continuation by
///   the `OutputReference` it claims, so several UTxOs can be settled in one
///   transaction without one continuation swallowing another: a single output
///   can only satisfy the single input it names.
pub type CounterDatum {
  count: Int,
  owner: Credential,
  prev_input: Option<OutputReference>,
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

/// Whether `input` is settled by a continuation output at `target_address`
/// whose inline datum is exactly `expected`.
///
/// Continuations are matched by full datum equality — including the
/// `prev_input` tag naming the UTxO they continue — so the lookup is a plain
/// `Data` comparison: no casting of foreign outputs, and one output can only
/// ever satisfy the single input it names.
///
/// The continuation must also carry no reference script and preserve the
/// input's non-ADA assets exactly, so a permissionless tick cannot bloat the
/// UTxO with attached scripts or smuggle tokens in (or drop state assets).
fn settled_by(
  self: Transaction,
  target_address: Address,
  expected: Data,
  input: Output,
) -> Bool {
  list.any(
    self.outputs,
    fn(out) {
      out.address == target_address && out.datum == InlineDatum(expected) && out.reference_script == None && assets.without_lovelace(
        out.value,
      ) == assets.without_lovelace(input.value) && assets.lovelace_of(out.value) >= assets.lovelace_of(
        input.value,
      )
    },
  )
}

/// Validate a forced counter tick: the input referenced by `own_ref` must be
/// settled by a continuation at its own address — one whose datum names
/// `own_ref` as its `prev_input` — that increments `count` by one, preserves
/// `owner` and the non-ADA assets, carries no reference script, and does not
/// decrease the lovelace held.
pub fn validate_counter_tick(
  self: Transaction,
  own_ref: OutputReference,
) -> Bool {
  expect Some(input) = find_input(self.inputs, own_ref)
  expect InlineDatum(in_raw) = input.output.datum
  expect CounterDatum { count, owner, .. } = in_raw

  let continuation: Data = CounterDatum {
    count: count + 1,
    owner,
    prev_input: Some(own_ref),
  }

  settled_by(self, input.output.address, continuation, input.output)
}

/// Validate an opt-in migration of the input referenced by `own_ref`: the same
/// state must reappear at `v2_address` — in a continuation whose datum names
/// `own_ref` as its `prev_input` — with `count`, `owner` and the non-ADA assets
/// preserved, no reference script, and no decrease in lovelace.
pub fn validate_counter_migrate(
  self: Transaction,
  own_ref: OutputReference,
  v2_address: Address,
) -> Bool {
  expect Some(input) = find_input(self.inputs, own_ref)
  expect InlineDatum(in_raw) = input.output.datum
  expect CounterDatum { count, owner, .. } = in_raw

  let continuation: Data = CounterDatum {
    count,
    owner,
    prev_input: Some(own_ref),
  }

  settled_by(self, v2_address, continuation, input.output)
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
