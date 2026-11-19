use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use upgradeability/counter.{carries_state_token}
use upgradeability/delegate.{Delegated, delegated_to}
use upgradeability/stepped_counter.{
  validate_stepped_genesis, validate_stepped_tick,
}
use withdraw_zero.{accept_registration}

/// The counter logic after a schema upgrade: reads both counter shapes and
/// writes `Stepped`, so a repoint from `counter_logic` converts each counter
/// the next time it is ticked.
validator counter_logic_stepped(
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
          carries_state_token(input) && validate_stepped_tick(
            self,
            input.output_reference,
          )
        },
      ),
      list.all(mints, fn(policy) { validate_stepped_genesis(self, policy) }),
      withdrawals == [],
      certificates == [],
      votes == [],
    }
  }

  publish(_redeemer: Data, certificate: Certificate, _self: Transaction) {
    accept_registration(certificate)
  }

  else(_) {
    fail
  }
}
