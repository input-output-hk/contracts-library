//// Reference validator for the delegated `full_recipient_deny_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): no listed full
//// address may receive the wallet's funds. Consumers may use it as-is or
//// embed `no_denied_recipients` in their own validators.

use cardano/address.{Address, Credential, Script}
use cardano/assets.{AssetName}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/full_recipient_list_logic.{
  no_denied_recipients,
}

/// Delegated deny-list script (withdraw-0). Requires no payout output — no
/// output not at the wallet's payment credential — to go to a full address
/// listed in `denied`.
validator full_recipient_deny_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  denied: List<Address>,
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
    no_denied_recipients(self, wallet, denied)
  }

  else(_) {
    fail
  }
}
