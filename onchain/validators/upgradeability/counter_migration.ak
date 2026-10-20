use aiken/collection/list
use cardano/address.{Address, Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Transaction}
use upgradeability/counter.{spent_with_upgrade, validate_counter_migrate}
use upgradeability/registry.{forwarded_inputs, get_registry}

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
    expect Script(own_hash) = account
    let registry = get_registry(self, settings_policy, settings_token_name)
    let targets = forwarded_inputs(self.inputs, registry, own_hash)
    list.all(
      targets,
      fn(input) {
        and {
          spent_with_upgrade(self, input.output_reference),
          validate_counter_migrate(self, input.output_reference, v2_address),
        }
      },
    )
  }

  else(_) {
    fail
  }
}
