//// Reference validator for a stateful `spending_window` withdrawal script:
//// limits the wallet to at most one spend per `window` milliseconds. See
//// `lib/smart_wallet/spending_window.ak` for the state type and logic.

use cardano/address.{Credential, Script}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/checks
use smart_wallet/spending_window_logic.{initial_state_valid, validate_withdraw}

validator spending_window(wallet: Credential, window: Int) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    when certificate is {
      RegisterCredential { credential: Script(own_hash), .. } ->
        initial_state_valid(checks.own_withdrawal_data(self, wallet, own_hash))
      UnregisterCredential { credential: Script(own_hash), .. } ->
        checks.own_withdrawal_removed(self, wallet, own_hash)
      _ -> fail
    }
  }

  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    expect Script(own_hash) = account
    validate_withdraw(self, wallet, own_hash, window)
  }

  else(_) {
    fail
  }
}
