//// Reference validator for the delegated `asset_deposit_deny_list` withdrawal
//// script (see `docs/smart-wallet/design.typ`): no asset class entering a
//// wallet on a `Deposit` may be listed in `denied`. A policy listed with an
//// empty name list denies all of its names; otherwise only the listed names
//// are denied. Consumers may use it as-is or embed `no_denied_assets_moved` in
//// their own validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/asset_list_logic.{no_denied_assets_moved}

/// Delegated asset deposit deny-list script. Requires no asset class moved by
/// the deposit to be listed in `denied`.
validator asset_deposit_deny_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  denied: Pairs<PolicyId, List<AssetName>>,
) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    withdrawal.reference_publish(
      certificate,
      self,
      wallet,
      wallet_token_name,
      withdrawal.Depositor,
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
      withdrawal.Depositor,
      fn(t) { no_denied_assets_moved(t, wallet, wallet_token_name, denied) },
    )
  }

  else(_) {
    fail
  }
}
