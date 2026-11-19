//// Reference validator for the delegated `asset_allow_list` withdrawal script
//// (see `docs/smart-wallet/design.typ`): the asset classes leaving a wallet on
//// a `Spend` must be authorised by `allowed`. A policy listed with an empty
//// name list allows any of its names; a policy absent allows none. Consumers
//// may use it as-is or embed `only_allowed_assets_moved` in their own
//// validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/asset_list_logic.{only_allowed_assets_moved}

/// Delegated asset allow-list script (withdraw-0). Requires every asset class
/// that moves in the transaction to be authorised by `allowed`.
validator asset_allow_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  allowed: Pairs<PolicyId, List<AssetName>>,
) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    withdrawal.reference_publish(
      certificate,
      self,
      wallet,
      wallet_token_name,
      withdrawal.Spender,
      withdrawal.stateless_data_valid,
    )
  }

  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    expect Script(own_hash) = account
    withdrawal.reference_withdraw(
      self,
      wallet,
      wallet_token_name,
      own_hash,
      withdrawal.Spender,
      fn(t) { only_allowed_assets_moved(t, wallet, wallet_token_name, allowed) },
    )
  }

  else(_) {
    fail
  }
}
