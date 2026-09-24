//// Reference validators for the smart wallet (see `docs/smart-wallet/design.typ`).
//// Thin wrappers over the reusable predicates in `lib/smart_wallet/checks.ak`:
//// `wallet_spend` is the spending script with its base M-of-N floor, and
//// `spending_limit` is an example delegated withdrawal script that bounds the
//// wallet's net outflow. Consumers may use these as-is or embed the `checks`
//// functions in their own validators.

use aiken/collection/list
use authorization
use cardano/address.{Credential}
use cardano/assets.{AssetName, Lovelace, PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use smart_wallet/checks
use smart_wallet/types.{Spend, UpdateWithdrawals, WalletDatum, WalletRedeemer}

/// Spending script. Its datum carries the delegated `withdrawals` list; the
/// `admin` credential allowed to change it is a script parameter. `Spend`
/// releases funds when at least `threshold` of `members` (read from the wallet
/// configuration) sign **and** every delegated withdrawal script in the datum
/// is invoked. `UpdateWithdrawals` lets the `admin` rewrite that list in place.
validator wallet_spend(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  admin: Credential,
) {
  spend(
    datum: Option<WalletDatum>,
    redeemer: WalletRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(wallet_datum) = datum
    when redeemer is {
      Spend ->
        checks.signed_m_of_n(self, settings_policy, settings_token_name) && checks.withdrawals_invoked(
          wallet_datum.withdrawals,
          self.withdrawals,
        )
      UpdateWithdrawals { out_ix } ->
        validate_withdrawals_update(admin, out_ix, own_ref, self)
    }
  }

  else(_) {
    fail
  }
}

/// Authorized rewrite of a wallet UTxO's `withdrawals` list: the script's
/// `admin` parameter must approve, and the continuation at `out_ix` must sit at
/// the same address with the same value — only `withdrawals` may change, so an
/// update cannot move funds.
fn validate_withdrawals_update(
  admin: Credential,
  out_ix: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect
    authorization.is_authorized(admin, self.extra_signatories, self.withdrawals)
  expect Some(own_input) = find_input(self.inputs, own_ref)
  expect Some(continuation) = list.at(self.outputs, out_ix)
  expect InlineDatum(raw) = continuation.datum
  expect _new_datum: WalletDatum = raw
  and {
    continuation.address == own_input.output.address,
    continuation.value == own_input.output.value,
  }
}

/// Delegated spending-limit script (withdraw-0). Requires the wallet's net
/// outflow `input - output` to stay below `bound` lovelace.
validator spending_limit(wallet: Credential, bound: Lovelace) {
  withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
    checks.within_spending_limit(self, wallet, bound)
  }

  else(_) {
    fail
  }
}
