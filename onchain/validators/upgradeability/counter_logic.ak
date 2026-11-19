use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use upgradeability/counter.{
  carries_state_token, validate_counter_genesis, validate_counter_tick,
}
use upgradeability/delegate.{Delegated, delegated_to}
use withdraw_zero.{accept_registration}

/// Forced logic for the counter demo (withdraw-0). Validates everything
/// delegated to it: genuine counters tick, mints are genesis only, and any
/// other kind of item is rejected.
validator counter_logic(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) {
  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    let Delegated { inputs, mints, withdrawals, certificates, votes } = delegated_to(
      self,
      settings_policy,
      settings_token_name,
      account,
    )
    and {
      list.all(
        inputs,
        fn(input) {
          carries_state_token(input) && validate_counter_tick(
            self,
            input.output_reference,
          )
        },
      ),
      list.all(mints, fn(policy) { validate_counter_genesis(self, policy) }),
      withdrawals == [],
      certificates == [],
      votes == [],
    }
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
