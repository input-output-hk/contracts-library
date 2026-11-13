//// Reference validator for the delegated `payment_staking_allow_list`
//// withdrawal script (see `docs/smart-wallet/design.typ`): a payout must
//// carry a payment credential listed in `allowed_payments` and an inline
//// staking credential listed in `allowed_stakings`; either list left empty
//// leaves its dimension unrestricted. Consumers may use it as-is or embed
//// `only_allowed_recipients` in their own validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/payment_staking_list_logic.{
  only_allowed_recipients,
}

/// Delegated payment/staking allow-list script (withdraw-0). Payment and
/// staking credential moves must each be authorised by their list.
validator payment_staking_allow_list(
  wallet: Credential,
  wallet_token_name: AssetName,
  allowed_payments: List<Credential>,
  allowed_stakings: List<Credential>,
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
        only_allowed_recipients(t, wallet, allowed_payments, allowed_stakings)
      },
    )
  }

  else(_) {
    fail
  }
}
