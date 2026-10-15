//// Smart wallet — stateful `spending_period_limit` withdrawal script.
////
//// A delegated withdraw-0 script that caps the wallet's cumulative lovelace
//// outflow per fixed time period: at most `max_spend` lovelace per `interval`
//// milliseconds. Periods are anchored to fixed multiples of `interval` (POSIX
//// ms), so the window never slips when nothing is spent early in a cycle.
////
//// Like `spending_window`, this script carries mutable state (the current
//// period boundary and the amount spent so far) in the wallet datum's
//// `spenders` map.

use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite}
use cardano/address.{Credential}
use cardano/assets.{Lovelace, Value}
use cardano/transaction.{Output, Transaction}
use smart_wallet/withdrawal

/// Mutable state: `period` is the end (POSIX ms) of the current period, a fixed
/// multiple of the script's `interval`; `0` means no period has started yet.
/// `acc_spend` is the lovelace spent so far in that period.
pub type SpendingPeriodState {
  period: Int,
  acc_spend: Int,
}

/// The initial state a wallet must store when adding this script: no period
/// started and nothing spent.
pub fn initial_state_valid(data: Data) -> Bool {
  expect state: SpendingPeriodState = data
  and {
    state.period == 0,
    state.acc_spend == 0,
  }
}

/// Validate one `Spend`: enforces the per-period budget and the exact state
/// transition. Reads the current state from the wallet input datum and the next
/// state from the wallet output datum, so the transition is enforced end-to-end
/// by this script.
///
/// `tx_spend` is the wallet's net lovelace outflow (`input - output` summed at
/// the wallet credential). Within a period it is added to the accumulator; once
/// `now` passes the stored boundary the period rolls over to the next fixed
/// multiple of `interval` and the accumulator restarts at `tx_spend`.
pub fn validate_withdraw(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
  interval: Int,
  max_spend: Lovelace,
) -> Bool {
  expect Finite(now) = self.validity_range.lower_bound.bound_type
  expect current: SpendingPeriodState = withdrawal.own_withdrawal_data_in(
    self,
    wallet,
    own_hash,
  )
  expect next: SpendingPeriodState = withdrawal.own_withdrawal_data(
    self,
    wallet,
    own_hash,
  )
  let tx_spend = net_outflow(self, wallet)
  let within_period = now <= current.period
  let within_cap = if within_period {
    current.acc_spend + tx_spend <= max_spend
  } else {
    tx_spend <= max_spend
  }
  let expected_period = if within_period {
    current.period
  } else {
    next_period_boundary(now, interval)
  }
  let expected_acc = if within_period {
    current.acc_spend + tx_spend
  } else {
    tx_spend
  }
  and {
    within_cap,
    next.period == expected_period,
    next.acc_spend == expected_acc,
  }
}

/// The end of the fixed-grid period containing `now`: the next multiple of
/// `interval` strictly greater than `now`.
fn next_period_boundary(now: Int, interval: Int) -> Int {
  ( now / interval + 1 ) * interval
}

/// Net lovelace outflow at the wallet credential: the summed input value minus
/// the summed output value across the UTxOs sitting at `wallet`.
fn net_outflow(self: Transaction, wallet: Credential) -> Lovelace {
  let input = sum_at_credential(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
  )
  let output = sum_at_credential(self.outputs, wallet)
  assets.lovelace_of(input) - assets.lovelace_of(output)
}

/// Aggregate value across `outputs` whose payment credential is `credential`.
fn sum_at_credential(outputs: List<Output>, credential: Credential) -> Value {
  list.foldl(
    outputs,
    assets.zero,
    fn(output, acc) {
      if output.address.payment_credential == credential {
        assets.merge(acc, output.value)
      } else {
        acc
      }
    },
  )
}
