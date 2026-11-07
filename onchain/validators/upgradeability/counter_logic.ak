use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use upgradeability/counter.{validate_counter_tick}
use upgradeability/delegate.{forwarded_by}
use withdraw_zero.{accept_registration}

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

  /// Registering this script's stake credential is the only certificate it
  /// accepts: withdraw-0 needs it registered, and refusing deregistration
  /// keeps every forwarder that points here from getting stuck.
  publish(_redeemer: Data, certificate: Certificate, _self: Transaction) {
    accept_registration(certificate)
  }

  else(_) {
    fail
  }
}
