//// Reference validator for a stateful `spending_period_limit` withdrawal
//// script: caps the wallet's cumulative lovelace outflow to `max_spend` per
//// fixed `interval`-millisecond period. See
//// `lib/smart_wallet/withdrawal_scripts/spending_period_limit_logic.ak` for the
//// state type and logic.

use cardano/address.{Credential, Script}
use cardano/assets.{Lovelace}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/spending_period_limit_logic.{
  initial_state_valid, validate_withdraw,
}

validator spending_period_limit(
  wallet: Credential,
  interval: Int,
  max_spend: Lovelace,
) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    when certificate is {
      RegisterCredential { credential: Script(own_hash), .. } ->
        initial_state_valid(
          withdrawal.own_withdrawal_data(self, wallet, own_hash),
        )
      UnregisterCredential { credential: Script(own_hash), .. } ->
        withdrawal.own_withdrawal_removed(self, wallet, own_hash)
      _ -> fail
    }
  }

  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    expect Script(own_hash) = account
    validate_withdraw(self, wallet, own_hash, interval, max_spend)
  }

  else(_) {
    fail
  }
}
