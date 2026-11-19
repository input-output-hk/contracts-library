//// Reference validator for the delegated `full_recipient_allow_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): only the listed
//// full addresses may receive the wallet's funds. Consumers may use it as-is
//// or embed `only_allowed_recipients` in their own validators.

use cardano/address.{Address, Credential, Script}
use cardano/assets.{AssetName}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/full_recipient_list_logic.{
  only_allowed_recipients,
}

/// Delegated allow-list script (withdraw-0). Requires every payout output —
/// every output not at the wallet's payment credential — to go to a full
/// address listed in `allowed`.
validator full_recipient_allow_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  allowed: List<Address>,
) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    when certificate is {
      RegisterCredential { credential: Script(own_hash), .. } ->
        withdrawal.stateless_data_valid(
          withdrawal.own_withdrawal_data(
            self,
            wallet,
            wallet_token_name,
            own_hash,
          ),
        )
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

  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    expect Script(own_hash) = account
    and {
      withdrawal.own_withdrawal_stateless_unchanged(
        self,
        wallet,
        wallet_token_name,
        own_hash,
      ),
      only_allowed_recipients(self, wallet, allowed),
    }
  }

  else(_) {
    fail
  }
}
