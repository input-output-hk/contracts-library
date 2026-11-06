use aiken/collection/pairs
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use upgradeability/registry.{get_registry, lookup, own_script_hash}

/// Forced forwarding (beacon indirection).
///
/// A thin forwarder admits a spend **iff** the script registered for its own
/// hash is invoked as a reward withdrawal in the same transaction (the
/// withdraw-0 convention). The registered script — not this forwarder — carries
/// the protocol's logic and is responsible for validating the forwarded input.
///
/// This predicate is O(1) and asserts only about:
///
/// - the forwarder's own input (via `own_ref`),
/// - the settings UTxO (reference input) that holds the registry, and
/// - the presence of the delegate's withdrawal key.
///
/// It makes no claim about the number of inputs/outputs, the total value, or
/// unrelated UTxOs, so it satisfies `docs/ARCHITECTURE.md` §1.1.
///
/// **Load-bearing constraint.** A validator only becomes forced-upgradeable if
/// *every* redeemer path calls this predicate from day one. A plain validator
/// that adds a dedicated `Upgrade` path later is opt-in, not forced.
pub fn validate_forward(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, withdrawals, .. } = self
  let registry = get_registry(self, settings_policy, settings_token_name)
  let own = own_script_hash(inputs, own_ref)
  when lookup(registry, own) is {
    Some(logic_hash) -> pairs.has_key(withdrawals, Script(logic_hash))
    None -> False
  }
}
