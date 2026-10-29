//// Reference validator for the delegated `full_recipient_allow_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): only the listed
//// full addresses may receive the wallet's funds. Consumers may use it as-is
//// or embed `only_allowed_recipients` in their own validators.

use cardano/address.{Address, Credential, Script}
use cardano/assets.{AssetName}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/full_recipient_list_logic.{
  only_allowed_recipients,
}

/// Delegated full-recipient allow-list script (withdraw-0). Only the listed
/// full addresses may receive the wallet's funds.
validator full_recipient_allow_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  allowed: List<Address>,
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
      fn(t) { only_allowed_recipients(t, wallet, allowed) },
    )
  }

  else(_) {
    fail
  }
}
