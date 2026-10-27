//// Reference validator for the delegated `spending_limit` withdrawal script
//// (see `docs/smart-wallet/design.typ`): bounds the wallet's net outflow to
//// `bound` lovelace. Consumers may use it as-is or embed
//// `within_spending_limit` in their own validators.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, Lovelace}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/spending_limit_logic.{within_spending_limit}

/// Delegated spending-limit script (withdraw-0): net outflow stays below
/// `bound` for each deposit.
validator spending_limit(
  wallet: Credential,
  wallet_token_name: AssetName,
  bound: Lovelace,
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
      fn(t) { within_spending_limit(t, wallet, wallet_token_name, bound) },
    )
  }

  else(_) {
    fail
  }
}
