//// Smart wallet — stateful `spending_window` withdrawal script.
////
//// A delegated withdraw-0 script that limits how often the wallet can spend: at
//// most one spend per `window` milliseconds. Unlike `spending_limit`, whose
//// `bound` is a fixed compile-time parameter, this script carries mutable state
//// (the upper bound of the previous spend's validity range) in the wallet
//// datum's `spenders` map.

use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite}
use cardano/address.{Credential}
use cardano/assets.{AssetName}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal

/// Mutable state: the POSIX time (ms) of the previous spend's validity-range
/// upper bound; `0` means never spent. The upper bound is the latest possible
/// execution time of that spend, so the next spend can be required to start at
/// least `window` milliseconds after it.
pub type SpendingWindowState {
  last_upper: Int,
}

/// The initial state a wallet must store when adding this script: never spent.
pub fn initial_state_valid(data: Data) -> Bool {
  expect state: SpendingWindowState = data
  state.last_upper == 0
}

/// Validate one `Spend`: both validity bounds must be finite, at least `window`
/// milliseconds must separate this spend's lower bound from the previous spend's
/// upper bound, and the wallet output must record this spend's upper bound.
/// Reads the current state from the wallet input datum and the next state from
/// the wallet output datum, so the state transition is enforced end-to-end by
/// this script.
pub fn validate_withdraw(
  self: Transaction,
  wallet: Credential,
  wallet_token_name: AssetName,
  own_hash: ScriptHash,
  window: Int,
) -> Bool {
  expect Finite(lower) = self.validity_range.lower_bound.bound_type
  expect Finite(upper) = self.validity_range.upper_bound.bound_type
  expect current: SpendingWindowState = withdrawal.own_withdrawal_data_in(
    self,
    wallet,
    wallet_token_name,
    own_hash,
  )
  expect next: SpendingWindowState = withdrawal.own_withdrawal_data(
    self,
    wallet,
    wallet_token_name,
    own_hash,
  )
  let first_spend = current.last_upper == 0
  let cooldown_elapsed = lower - current.last_upper >= window
  ( first_spend || cooldown_elapsed ) && next.last_upper == upper
}
