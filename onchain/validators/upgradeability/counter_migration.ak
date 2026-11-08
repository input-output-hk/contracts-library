use aiken/collection/list
use cardano/address.{Address, Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use upgradeability/counter.{spent_with_upgrade, validate_counter_migrate}
use upgradeability/delegate.{forwarded_by}
use withdraw_zero.{accept_registration}

/// Opt-in migration script for the counter demo.
///
/// Runs under the withdraw-0 convention when a V1 UTxO is upgraded. It
/// validates every V1 input registered to delegate to this script: each must
/// have been spent with the `Upgrade` action and must reappear, with its state
/// preserved, at `v2_address`.
validator counter_migration(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  v2_address: Address,
) {
  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    list.all(
      forwarded_by(self, settings_policy, settings_token_name, account),
      fn(input) {
        and {
          spent_with_upgrade(self, input.output_reference),
          validate_counter_migrate(self, input.output_reference, v2_address),
        }
      },
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
