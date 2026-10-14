//// Reference validator for the delegated `asset_allow_list` withdrawal script
//// (see `docs/smart-wallet/design.typ`): the asset classes leaving a wallet on
//// a `Spend` must be authorised by `allowed`. A policy listed with an empty
//// name list allows any of its names; a policy absent allows none. Consumers
//// may use it as-is or embed `only_allowed_assets_moved` in their own
//// validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/asset_list_logic.{only_allowed_assets_moved}

/// Delegated asset allow-list script (withdraw-0). Requires every asset class
/// that moves in the transaction to be authorised by `allowed`.
validator asset_allow_list(
  wallet: Credential,
  allowed: Pairs<PolicyId, List<AssetName>>,
) {
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
    only_allowed_assets_moved(self, wallet, allowed)
  }

  else(_) {
    fail
  }
}
