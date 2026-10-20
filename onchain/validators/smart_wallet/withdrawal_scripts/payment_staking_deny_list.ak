//// Reference validator for the delegated `payment_staking_deny_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): a payout must not
//// carry a payment credential listed in `denied_payments` nor an inline
//// staking credential listed in `denied_stakings`; either list left empty
//// leaves its dimension unrestricted. Consumers may use it as-is or embed
//// `no_denied_recipients` in their own validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/payment_staking_list_logic.{
  no_denied_recipients,
}

/// Delegated payment/staking deny-list script (withdraw-0). Requires no payout
/// output — no output not at the wallet's payment credential — to carry a
/// listed payment credential or a listed inline staking credential.
validator payment_staking_deny_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  denied_payments: List<Credential>,
  denied_stakings: List<Credential>,
) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    when certificate is {
      RegisterCredential { credential: Script(own_hash), .. } -> {
        // stateless: only confirm this script is listed in the wallet datum; a
        // stateful script would additionally validate its initial `Data` here.
        expect _: Data = withdrawal.own_withdrawal_data(
          self,
          wallet,
          wallet_token_name,
          own_hash,
        )
        True
      }
      UnregisterCredential { credential: Script(own_hash), .. } ->
        // only allow unregistration when this script is leaving a wallet, so it
        // cannot be unregistered out of band (which would brick the wallet).
        withdrawal.own_withdrawal_removed(
          self,
          wallet,
          wallet_token_name,
          own_hash,
        )
      _ -> fail
    }
  }

  withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
    no_denied_recipients(self, wallet, denied_payments, denied_stakings)
  }

  else(_) {
    fail
  }
}
