use aiken/collection/list
use cardano/address.{Address, Credential}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_input,
}
use upgradeability/delegate.{spend_redeemer}

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
/// input's non-ADA assets exactly (`assets.match` compares the token bundle
/// exhaustively and delegates ADA to `>=`), so a permissionless tick cannot
/// bloat the UTxO with attached scripts or smuggle tokens in (or drop state
/// assets).
fn settled_by(
  self: Transaction,
  target_address: Address,
  expected: Data,
  input: Output,
) -> Bool {
  list.any(
    self.outputs,
    fn(out) {
      out.address == target_address && out.datum == InlineDatum(expected) && out.reference_script == None && assets.match(
        out.value,
        input.value,
        >=,
      )
    },
  )
}

/// Validate a forced counter tick: the input referenced by `own_ref` must be
/// settled by a continuation at its own address that increments `count` by
/// one (see `continue_counter`).
pub fn validate_counter_tick(
  self: Transaction,
  own_ref: OutputReference,
) -> Bool {
  continue_counter(self, own_ref, None, 1)
}

/// Validate an opt-in migration of the input referenced by `own_ref`: the same
/// state must reappear at `v2_address` with `count` unchanged (see
/// `continue_counter`).
pub fn validate_counter_migrate(
  self: Transaction,
  own_ref: OutputReference,
  v2_address: Address,
) -> Bool {
  continue_counter(self, own_ref, Some(v2_address), 0)
}

/// Settle the counter input referenced by `own_ref` with a continuation at
/// `target` (its own address when `None`) whose datum adds `increment` to
/// `count`, preserves `owner`, and names `own_ref` as its `prev_input`. The
/// continuation must also preserve the non-ADA assets, carry no reference
/// script, and not decrease the lovelace held (see `settled_by`).
fn continue_counter(
  self: Transaction,
  own_ref: OutputReference,
  target: Option<Address>,
  increment: Int,
) -> Bool {
  expect Some(input) = find_input(self.inputs, own_ref)
  expect InlineDatum(in_raw) = input.output.datum
  expect CounterDatum { count, owner, .. } = in_raw

  let continuation: Data = CounterDatum {
    count: count + increment,
    owner,
    prev_input: Some(own_ref),
  }
  let target_address = when target is {
    Some(address) -> address
    None -> input.output.address
  }

  settled_by(self, target_address, continuation, input.output)
}

/// Whether the input referenced by `ref` was spent with the `Upgrade` action.
///
/// A migration script uses this to bind a forwarded V1 input to the upgrade
/// path, so a V1 UTxO cannot be migrated while being spent under a normal
/// action.
pub fn spent_with_upgrade(self: Transaction, ref: OutputReference) -> Bool {
  let upgrade: Data = Upgrade
  spend_redeemer(self, ref) == Some(upgrade)
}
