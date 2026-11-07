use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Transaction}
use upgradeability/counter.{validate_counter_tick}
use upgradeability/registry.{forwarded_by}

/// Forced logic for the counter demo.
///
/// Runs under the withdraw-0 convention. It validates **every** transaction
/// input whose address is registered to delegate to this script, applying the
/// counter step to each. Validating all of them (rather than just one) is what
/// stops an attacker from having the logic check a benign input while another
/// forwarded input is spent unchecked.
///
/// Upgrading the protocol means deploying a new logic script with this same
/// parameterization and repointing the registry entry for the forwarder.
validator counter_logic(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) {
  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    list.all(
      forwarded_by(self, settings_policy, settings_token_name, account),
      fn(input) { validate_counter_tick(self, input.output_reference) },
    )
  }

  else(_) {
    fail
  }
}
