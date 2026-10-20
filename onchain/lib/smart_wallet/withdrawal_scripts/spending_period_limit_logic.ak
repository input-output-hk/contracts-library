//// Smart wallet — stateful `spending_period_limit` withdrawal script.
////
//// A delegated withdraw-0 script that caps the wallet's cumulative lovelace
//// outflow per fixed time period: at most `max_spend` lovelace per `interval`
//// milliseconds. Periods are `[start, end)` buckets anchored to fixed
//// multiples of `interval` (POSIX ms), so the window never slips when nothing
//// is spent early in a cycle.
////
//// Like `spending_window`, this script carries mutable state (the current
//// period boundary and the amount spent so far) in the wallet datum's
//// `spenders` map.

use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, Lovelace, Value, has_nft}
use cardano/transaction.{Output, Transaction}
use smart_wallet/withdrawal

/// Mutable state: `period` is the end (POSIX ms) of the charged period, a fixed
/// multiple of the script's `interval`; `0` means no period has started yet.
/// Periods are `[start, end)` buckets; `acc_spend` is the lovelace spent so far
/// in that period.
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

/// Whether the script parameters are usable: a positive period length and a
/// non-negative budget.
pub fn params_valid(interval: Int, max_spend: Lovelace) -> Bool {
  interval > 0 && max_spend >= 0
}

/// Validate one `Spend`: both validity bounds must be finite and lie in the
/// same `[start, end)` period, so the charged period contains the transaction's
/// whole validity interval. Within the stored period the outflow accumulates; a
/// later period rolls over; a historical period is rejected. Reads the current
/// state from the wallet input datum and the next state from the wallet output
/// datum, so the transition is enforced end-to-end by this script.
///
/// `tx_spend` is the wallet's net lovelace outflow (`input - output` summed at
/// the wallet credential).
pub fn validate_withdraw(
  self: Transaction,
  wallet: Credential,
  wallet_token_name: AssetName,
  own_hash: ScriptHash,
  interval: Int,
  max_spend: Lovelace,
) -> Bool {
  expect Finite(lower) = self.validity_range.lower_bound.bound_type
  expect Finite(upper) = self.validity_range.upper_bound.bound_type
  expect current: SpendingPeriodState = withdrawal.own_withdrawal_data_in(
    self,
    wallet,
    wallet_token_name,
    own_hash,
  )
  expect next: SpendingPeriodState = withdrawal.own_withdrawal_data(
    self,
    wallet,
    wallet_token_name,
    own_hash,
  )
  if params_valid(interval, max_spend) {
    let tx_spend = net_outflow(self, wallet, wallet_token_name)
    let period = period_end(lower, interval)
    let same_period = if self.validity_range.upper_bound.is_inclusive {
      upper < period
    } else {
      upper <= period
    }
    let same_as_current = current.period == period
    let within_cap = if same_as_current {
      current.acc_spend + tx_spend <= max_spend
    } else {
      tx_spend <= max_spend
    }
    let expected_acc = if same_as_current {
      current.acc_spend + tx_spend
    } else {
      tx_spend
    }
    and {
      same_period,
      period > 0,
      period >= current.period,
      within_cap,
      next.period == period,
      next.acc_spend == expected_acc,
    }
  } else {
    False
  }
}

/// The end of the `[start, end)` period containing `time`: the next multiple of
/// `interval` strictly greater than `time`.
fn period_end(time: Int, interval: Int) -> Int {
  ( time / interval + 1 ) * interval
}

/// Net lovelace outflow at the wallet: the summed input value minus the summed
/// output value across the NFT-bearing UTxOs sitting at `wallet`. NFT-less
/// outputs at the wallet address are not wallet funds and are ignored.
fn net_outflow(
  self: Transaction,
  wallet: Credential,
  wallet_token_name: AssetName,
) -> Lovelace {
  let input = sum_at_credential(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
    wallet_token_name,
  )
  let output = sum_at_credential(self.outputs, wallet, wallet_token_name)
  assets.lovelace_of(input) - assets.lovelace_of(output)
}

/// Aggregate value across `outputs` that sit at `credential` and carry the
/// wallet's NFT.
fn sum_at_credential(
  outputs: List<Output>,
  credential: Credential,
  wallet_token_name: AssetName,
) -> Value {
  expect Script(wallet_hash) = credential
  list.foldl(
    outputs,
    assets.zero,
    fn(output, acc) {
      if output.address.payment_credential == credential && has_nft(
        output.value,
        wallet_hash,
        wallet_token_name,
      ) {
        assets.merge(acc, output.value)
      } else {
        acc
      }
    },
  )
}
