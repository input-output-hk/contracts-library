//// Reference validator for the delegated `full_recipient_deny_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): no listed full
//// address may receive the wallet's funds. Consumers may use it as-is or
//// embed `no_denied_recipients` in their own validators.

use cardano/address.{Address, Credential, Script}
use cardano/assets.{AssetName}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/full_recipient_list_logic.{
  no_denied_recipients,
}

/// Delegated full-recipient deny-list script (withdraw-0). The listed full
/// addresses may not receive the wallet's funds.
validator full_recipient_deny_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  denied: List<Address>,
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
      fn(t) { no_denied_recipients(t, wallet, denied) },
    )
  }

  else(_) {
    fail
  }
}
