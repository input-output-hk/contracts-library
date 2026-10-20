//// Reference validator for the delegated `asset_deny_list` withdrawal script
//// (see `docs/smart-wallet/design.typ`): no asset class leaving a wallet on a
//// `Spend` may be listed in `denied`. A policy listed with an empty name list
//// denies all of its names; otherwise only the listed names are denied.
//// Consumers may use it as-is or embed `no_denied_assets_moved` in their own
//// validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/asset_list_logic.{no_denied_assets_moved}

/// Delegated asset deny-list script (withdraw-0). Requires no asset class that
/// moves in the transaction to be listed in `denied`.
validator asset_deny_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  denied: Pairs<PolicyId, List<AssetName>>,
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
    no_denied_assets_moved(self, wallet, wallet_token_name, denied)
  }

  else(_) {
    fail
  }
}
