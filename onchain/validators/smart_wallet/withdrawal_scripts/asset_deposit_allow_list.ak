//// Reference validator for the delegated `asset_deposit_allow_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): the asset classes
//// entering a wallet on a `Deposit` must be authorised by `allowed`. A policy
//// listed with an empty name list allows any of its names; a policy absent
//// allows none. Consumers may use it as-is or embed `only_allowed_assets_moved`
//// in their own validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/asset_list_logic.{only_allowed_assets_moved}

/// Delegated asset allow-list deposit script (withdraw-0). Requires every asset
/// class that moves in the transaction to be authorised by `allowed`.
validator asset_deposit_allow_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  allowed: Pairs<PolicyId, List<AssetName>>,
) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    when certificate is {
      RegisterCredential { credential: Script(own_hash), .. } ->
        withdrawal.stateless_data_valid(
          withdrawal.own_depositor_data(
            self,
            wallet,
            wallet_token_name,
            own_hash,
          ),
        )
      UnregisterCredential { credential: Script(own_hash), .. } ->
        // only allow unregistration when this script is leaving a wallet, so it
        // cannot be unregistered out of band (which would brick the wallet).
        withdrawal.own_depositor_removed(
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
      withdrawal.own_depositor_stateless_unchanged(
        self,
        wallet,
        wallet_token_name,
        own_hash,
      ),
      only_allowed_assets_moved(self, wallet, wallet_token_name, allowed),
    }
  }

  else(_) {
    fail
  }
}
