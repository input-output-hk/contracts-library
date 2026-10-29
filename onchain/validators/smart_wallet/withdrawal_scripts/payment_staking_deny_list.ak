//// Reference validator for the delegated `payment_staking_deny_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): a payout must not
//// carry a payment credential listed in `denied_payments` nor an inline
//// staking credential listed in `denied_stakings`; either list left empty
//// leaves its dimension unrestricted. Consumers may use it as-is or embed
//// `no_denied_recipients` in their own validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/payment_staking_list_logic.{
  no_denied_recipients,
}

/// Delegated payment/staking deny-list script (withdraw-0). Payment and
/// staking credential moves must not be in their list.
validator payment_staking_deny_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  denied_payments: List<Credential>,
  denied_stakings: List<Credential>,
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
      fn(t) {
        no_denied_recipients(t, wallet, denied_payments, denied_stakings)
      },
    )
  }

  else(_) {
    fail
  }
}
