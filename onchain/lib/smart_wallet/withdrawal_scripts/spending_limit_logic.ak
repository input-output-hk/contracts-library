//// Smart wallet — the `spending_limit` withdrawal script's logic: bounds the
//// wallet's net lovelace outflow to a fixed `bound`.

use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{Lovelace, Value}
use cardano/transaction.{Output, Transaction}

/// Spending-limit check: the net lovelace outflow `input - output` stays
/// strictly below `bound`.
///
/// `input` and `output` are the aggregate values a caller has summed over the
/// wallet's inputs and outputs; the delegated withdrawal script passes those in
/// and asserts the outflow is bounded.
pub fn value_delta_below_bound(
  input: Value,
  output: Value,
  bound: Lovelace,
) -> Bool {
  assets.lovelace_of(input) - assets.lovelace_of(output) < bound
}

/// Whole-transaction spending-limit check: sums the value on UTxOs at `wallet`
/// across the inputs and outputs and bounds the net outflow with
/// `value_delta_below_bound`.
pub fn within_spending_limit(
  self: Transaction,
  wallet: Credential,
  bound: Lovelace,
) -> Bool {
  let input = sum_at_credential(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
  )
  let output = sum_at_credential(self.outputs, wallet)
  value_delta_below_bound(input, output, bound)
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
