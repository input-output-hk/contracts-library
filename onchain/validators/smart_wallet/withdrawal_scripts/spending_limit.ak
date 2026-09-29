//// Reference validator for the delegated `spending_limit` withdrawal script
//// (see `docs/smart-wallet/design.typ`): bounds the wallet's net outflow to
//// `bound` lovelace. Consumers may use it as-is or embed
//// `within_spending_limit` in their own validators.

use cardano/address.{Credential, Script}
use cardano/assets.{Lovelace}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/spending_limit_logic.{within_spending_limit}

/// Delegated spending-limit script (withdraw-0). Requires the wallet's net
/// outflow `input - output` to stay below `bound` lovelace.
validator spending_limit(wallet: Credential, bound: Lovelace) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    when certificate is {
      RegisterCredential { credential: Script(own_hash), .. } -> {
        // stateless: only confirm this script is listed in the wallet datum; a
        // stateful script would additionally validate its initial `Data` here.
        expect _: Data = withdrawal.own_withdrawal_data(self, wallet, own_hash)
        True
      }
      UnregisterCredential { credential: Script(own_hash), .. } ->
        // only allow unregistration when this script is leaving a wallet, so it
        // cannot be unregistered out of band (which would brick the wallet).
        withdrawal.own_withdrawal_removed(self, wallet, own_hash)
      _ -> fail
    }
  }

  withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
    within_spending_limit(self, wallet, bound)
  }

  else(_) {
    fail
  }
}
