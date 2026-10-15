//// Smart wallet — stateful `spending_window` withdrawal script.
////
//// A delegated withdraw-0 script that limits how often the wallet can spend: at
//// most one spend per `window` milliseconds. Unlike `spending_limit`, whose
//// `bound` is a fixed compile-time parameter, this script carries mutable state
//// (the last spend time) in the wallet datum's `spenders` map.

use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite}
use cardano/address.{Credential}
use cardano/transaction.{Transaction}
use smart_wallet/withdrawal

/// Mutable state: the POSIX time (ms) of the last spend; `0` means never spent.
pub type SpendingWindowState {
  last_spend: Int,
}

/// The initial state a wallet must store when adding this script: never spent.
pub fn initial_state_valid(data: Data) -> Bool {
  expect state: SpendingWindowState = data
  state.last_spend == 0
}

/// Validate one `Spend`: at least `window` milliseconds must have elapsed since
/// the last spend, and the wallet output must carry the updated state (this
/// spend's time). Reads the current state from the wallet input datum and the
/// next state from the wallet output datum, so the state transition is enforced
/// end-to-end by this script.
pub fn validate_withdraw(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
  window: Int,
) -> Bool {
  expect Finite(now) = self.validity_range.lower_bound.bound_type
  expect current: SpendingWindowState = withdrawal.own_withdrawal_data_in(
    self,
    wallet,
    own_hash,
  )
  expect next: SpendingWindowState = withdrawal.own_withdrawal_data(
    self,
    wallet,
    own_hash,
  )
  let first_spend = current.last_spend == 0
  let cooldown_elapsed = now - current.last_spend >= window
  ( first_spend || cooldown_elapsed ) && next.last_spend == now
}
