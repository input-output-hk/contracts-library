//// Smart wallet — the withdraw-0 script framework.
////
//// These helpers let a delegated withdraw-0 script read its own configuration
//// or mutable state (stored in the wallet datum's `spenders` or `depositors`
//// map, keyed by the script's own hash) and decide whether it is being
//// removed. They are used by delegated scripts' `publish` and `withdraw`
//// handlers, never by the core wallet.
////
//// A delegated script is trusted to be well-formed: the core validates neither
//// the size nor the semantics of its `Data`. It should validate its initial
//// `Data` in `publish`, verify its own input→output transition in `withdraw`
//// when stateful, keep its `Data` small (it is copied into every wallet UTxO),
//// rely on its own entry only, and accept `UnregisterCredential` when leaving —
//// a script that refuses to unregister blocks `Close` and removal.

use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use cardano/address.{Credential}
use cardano/transaction.{InlineDatum, Output, Transaction}
use smart_wallet/types.{WalletDatum}

/// The `Data` the wallet's output datum associates with `own_hash` in the
/// `spenders` map, i.e. a spender script's own initial (or current) mutable
/// state. Used by a spender script's `publish` handler to read and validate
/// its initial `Data` from the wallet UTxO.
pub fn own_withdrawal_data(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  own_data_from(self.outputs, wallet, own_hash, fn(datum) { datum.spenders })
}

/// Like [`own_withdrawal_data`](#own_withdrawal_data) but reads the wallet's
/// *input* datum (the wallet UTxO being spent), i.e. a spender script's own
/// *current* mutable state before this transaction. Used by a stateful spender
/// script's `withdraw` handler to read the state it is transitioning from.
pub fn own_withdrawal_data_in(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  own_data_from(
    input_outputs(self),
    wallet,
    own_hash,
    fn(datum) { datum.spenders },
  )
}

/// Whether `own_hash` is being *removed* from the `spenders` map in this
/// transaction: it is listed in the wallet's input datum but not in its output
/// datum (or there is no wallet output at all, as on `Close`). Used by a
/// spender script's `publish` handler to accept unregistration only when the
/// script is actually leaving a wallet, so it cannot be unregistered out of
/// band.
pub fn own_withdrawal_removed(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Bool {
  own_removed(self, wallet, own_hash, fn(datum) { datum.spenders })
}

/// The `Data` the wallet's output datum associates with `own_hash` in the
/// `depositors` map, i.e. a deposit script's own configuration. Used by a
/// deposit script's `publish` handler to read and validate its initial `Data`
/// from the wallet UTxO.
pub fn own_depositor_data(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  own_data_from(self.outputs, wallet, own_hash, fn(datum) { datum.depositors })
}

/// Like [`own_depositor_data`](#own_depositor_data) but reads the wallet's
/// *input* datum (the wallet UTxO being spent), i.e. a deposit script's own
/// current configuration before this transaction. Used by a deposit script's
/// `withdraw` handler to read the configuration it validates against.
pub fn own_depositor_data_in(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  own_data_from(
    input_outputs(self),
    wallet,
    own_hash,
    fn(datum) { datum.depositors },
  )
}

/// Whether `own_hash` is being *removed* from the `depositors` map in this
/// transaction: it is listed in the wallet's input datum but not in its output
/// datum (or there is no wallet output at all, as on `Close`). Used by a
/// deposit script's `publish` handler to accept unregistration only when the
/// script is actually leaving a wallet, so it cannot be unregistered out of
/// band.
pub fn own_depositor_removed(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Bool {
  own_removed(self, wallet, own_hash, fn(datum) { datum.depositors })
}

/// The `Data` the wallet's output datum associates with `own_hash` in the map
/// selected by `select`.
fn own_data_from(
  outputs: List<Output>,
  wallet: Credential,
  own_hash: ScriptHash,
  select: fn(WalletDatum) -> Pairs<ScriptHash, Data>,
) -> Data {
  expect Some(datum) = wallet_datum(outputs, wallet)
  expect Some(data) = pairs.get_first(select(datum), own_hash)
  data
}

/// Whether `own_hash` is being removed from the map selected by `select`.
fn own_removed(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
  select: fn(WalletDatum) -> Pairs<ScriptHash, Data>,
) -> Bool {
  expect Some(input_datum) = wallet_datum(input_outputs(self), wallet)
  let in_input = pairs.has_key(select(input_datum), own_hash)
  let in_output = when wallet_datum(self.outputs, wallet) is {
    Some(output_datum) -> pairs.has_key(select(output_datum), own_hash)
    None -> False
  }
  in_input && !in_output
}

/// The outputs of the transaction's inputs.
fn input_outputs(self: Transaction) -> List<Output> {
  list.map(self.inputs, fn(input) { input.output })
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
