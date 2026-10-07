//// Smart wallet — the withdrawal-script framework.
////
//// These helpers let a delegated withdraw-0 script read its own mutable state
//// (stored in the wallet datum's `spenders` map, keyed by the script's own
//// hash) and decide whether it is being removed. They are used by withdrawal
//// scripts' `publish` and `withdraw` handlers, never by the core wallet.

use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use cardano/address.{Credential}
use cardano/transaction.{InlineDatum, Output, Transaction}
use smart_wallet/types.{WalletDatum}

/// The `Data` the wallet's output datum associates with `own_hash`, i.e. a
/// withdrawal script's own initial (or current) mutable state. Used by a
/// withdrawal script's `publish` handler to read and validate its initial
/// `Data` from the wallet UTxO.
pub fn own_withdrawal_data(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  expect Some(datum) = wallet_datum(self.outputs, wallet)
  expect Some(data) = pairs.get_first(datum.spenders, own_hash)
  data
}

/// Like [`own_withdrawal_data`](#own_withdrawal_data) but reads the wallet's
/// *input* datum (the wallet UTxO being spent), i.e. a withdrawal script's own
/// *current* mutable state before this transaction. Used by a stateful
/// withdrawal script's `withdraw` handler to read the state it is transitioning
/// from.
pub fn own_withdrawal_data_in(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  expect Some(datum) = wallet_datum(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
  )
  expect Some(data) = pairs.get_first(datum.spenders, own_hash)
  data
}

/// Whether `own_hash` is being *removed* in this transaction: it is listed in
/// the wallet's input datum but not in its output datum (or there is no wallet
/// output at all, as on `Close`). Used by a withdrawal script's `publish`
/// handler to accept unregistration only when the script is actually leaving a
/// wallet, so it cannot be unregistered out of band.
pub fn own_withdrawal_removed(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Bool {
  expect Some(input_datum) = wallet_datum(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
  )
  let in_input = pairs.has_key(input_datum.spenders, own_hash)
  let in_output = when wallet_datum(self.outputs, wallet) is {
    Some(output_datum) -> pairs.has_key(output_datum.spenders, own_hash)
    None -> False
  }
  in_input && !in_output
}

/// The wallet UTxO's datum at `wallet`, if present among `outputs`.
fn wallet_datum(
  outputs: List<Output>,
  wallet: Credential,
) -> Option<WalletDatum> {
  when
    list.find(
      outputs,
      fn(output) { output.address.payment_credential == wallet },
    )
  is {
    Some(output) -> {
      expect InlineDatum(raw) = output.datum
      expect datum: WalletDatum = raw
      Some(datum)
    }
    None -> None
  }
}
