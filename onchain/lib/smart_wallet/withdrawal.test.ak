use aiken/cbor
use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal.{
  own_depositor_data, own_depositor_data_in, own_depositor_removed,
  own_withdrawal_data, own_withdrawal_removed,
}

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

// ------------------------------------------------------ own_withdrawal_data

test own_data_read_from_wallet_output() {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(
      WalletDatum { spenders: [Pair(a, data)], depositors: [] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  cbor.serialise(own_withdrawal_data(tx, Script(a), a)) == cbor.serialise(data)
}

test own_data_missing_script() fail {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(
      WalletDatum { spenders: [Pair(b, data)], depositors: [] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  expect _: Data = own_withdrawal_data(tx, Script(a), a)
}

test own_data_missing_wallet_output() fail {
  expect _: Data = own_withdrawal_data(placeholder, Script(a), a)
}

// ---------------------------------------------------- own_withdrawal_removed

fn wallet_output_at(spenders: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { spenders, depositors: [] }),
    reference_script: None,
  }
}

fn wallet_input_at(spenders: Pairs<ScriptHash, Data>) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output_at(spenders),
  }
}

test removed_with_input_and_no_output() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
  }
  own_withdrawal_removed(tx, Script(a), a)
}

test removed_with_input_and_empty_output() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
    outputs: [wallet_output_at([])],
  }
  own_withdrawal_removed(tx, Script(a), a)
}

test removed_rejects_when_kept() fail {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
    outputs: [wallet_output_at([Pair(a, data)])],
  }
  own_withdrawal_removed(tx, Script(a), a)
}

test removed_rejects_without_wallet_input() fail {
  own_withdrawal_removed(placeholder, Script(a), a)
}

// ------------------------------------------------------- own_depositor_data

test own_depositor_data_read_from_wallet_output() {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(
      WalletDatum { spenders: [], depositors: [Pair(a, data)] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  cbor.serialise(own_depositor_data(tx, Script(a), a)) == cbor.serialise(data)
}

test own_depositor_data_missing_script() fail {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(
      WalletDatum { spenders: [], depositors: [Pair(b, data)] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  expect _: Data = own_depositor_data(tx, Script(a), a)
}

test own_depositor_data_in_reads_wallet_input() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
  }
  cbor.serialise(own_depositor_data_in(tx, Script(a), a)) == cbor.serialise(
    data,
  )
}

// ---------------------------------------------------- own_depositor_removed

fn wallet_output_at_depositors(depositors: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { spenders: [], depositors }),
    reference_script: None,
  }
}

fn wallet_input_at_depositors(depositors: Pairs<ScriptHash, Data>) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output_at_depositors(depositors),
  }
}

test depositor_removed_with_input_and_no_output() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
  }
  own_depositor_removed(tx, Script(a), a)
}

test depositor_removed_with_input_and_empty_output() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
    outputs: [wallet_output_at_depositors([])],
  }
  own_depositor_removed(tx, Script(a), a)
}

test depositor_removed_rejects_when_kept() fail {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
    outputs: [wallet_output_at_depositors([Pair(a, data)])],
  }
  own_depositor_removed(tx, Script(a), a)
}

test depositor_removed_rejects_without_wallet_input() fail {
  own_depositor_removed(placeholder, Script(a), a)
}
