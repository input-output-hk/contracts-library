//// Reference validator for a stateful `spending_period_limit` withdrawal
//// script: caps the wallet's cumulative lovelace outflow to `max_spend` per
//// fixed `interval`-millisecond period. See
//// `lib/smart_wallet/withdrawal_scripts/spending_period_limit_logic.ak` for the
//// state type and logic.

use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, Lovelace}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal
use smart_wallet/withdrawal_scripts/spending_period_limit_logic.{
  initial_state_valid, params_valid, validate_withdraw,
}

validator spending_period_limit(
  wallet: Credential,
  wallet_token_name: AssetName,
  interval: Int,
  max_spend: Lovelace,
) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    withdrawal.reference_publish(
      certificate,
      self,
      wallet,
      wallet_token_name,
      withdrawal.Spender,
      fn(d) { params_valid(interval, max_spend) && initial_state_valid(d) },
    )
  }

  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    expect Script(own_hash) = account
    validate_withdraw(
      self,
      wallet,
      wallet_token_name,
      own_hash,
      interval,
      max_spend,
    )
  }

  else(_) {
    fail
  }
}
