//// Smart wallet — the `spending_limit` withdrawal script's logic: bounds the
//// wallet's net lovelace outflow to a fixed `bound`.

use aiken/collection/list
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, Lovelace, Value, has_nft}
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

/// Whole-transaction spending-limit check: sums the value on NFT-bearing UTxOs
/// at `wallet` across the inputs and outputs and bounds the net outflow with
/// `value_delta_below_bound`. NFT-less outputs at the wallet address are not
/// wallet funds and are ignored.
pub fn within_spending_limit(
  self: Transaction,
  wallet: Credential,
  wallet_token_name: AssetName,
  bound: Lovelace,
) -> Bool {
  let input = sum_at_credential(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
    wallet_token_name,
  )
  let output = sum_at_credential(self.outputs, wallet, wallet_token_name)
  value_delta_below_bound(input, output, bound)
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
