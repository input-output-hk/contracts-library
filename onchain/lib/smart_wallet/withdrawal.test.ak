use aiken/cbor
use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, Script, VerificationKey, from_script}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal.{
  own_depositor_data, own_depositor_data_in, own_depositor_removed,
  own_depositor_stateless_unchanged, own_withdrawal_data, own_withdrawal_removed,
  own_withdrawal_stateless_unchanged, reference_publish, stateless_data_valid,
}

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const wallet_token = "wallet"

fn nft_value() -> assets.Value {
  assets.from_asset(a, wallet_token, 1)
}

// ------------------------------------------------------ own_withdrawal_data

test own_data_read_from_wallet_output() {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: nft_value(),
    datum: InlineDatum(
      WalletDatum { spenders: [Pair(a, data)], depositors: [] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  cbor.serialise(own_withdrawal_data(tx, Script(a), wallet_token, a)) == cbor.serialise(
    data,
  )
}

test own_data_missing_script() fail {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: nft_value(),
    datum: InlineDatum(
      WalletDatum { spenders: [Pair(b, data)], depositors: [] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  expect _: Data = own_withdrawal_data(tx, Script(a), wallet_token, a)
}

test own_data_missing_wallet_output() fail {
  expect _: Data = own_withdrawal_data(placeholder, Script(a), wallet_token, a)
}

test own_data_ignores_nft_less_decoy() {
  let real: Data = 1
  let decoy: Data = 2
  let decoy_output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(
      WalletDatum { spenders: [Pair(a, decoy)], depositors: [] },
    ),
    reference_script: None,
  }
  let real_output = Output {
    address: from_script(a),
    value: nft_value(),
    datum: InlineDatum(
      WalletDatum { spenders: [Pair(a, real)], depositors: [] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [decoy_output, real_output] }
  cbor.serialise(own_withdrawal_data(tx, Script(a), wallet_token, a)) == cbor.serialise(
    real,
  )
}

// ---------------------------------------------------- own_withdrawal_removed

fn wallet_output_at(spenders: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(a),
    value: nft_value(),
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
  own_withdrawal_removed(tx, Script(a), wallet_token, a)
}

test removed_with_input_and_empty_output() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
    outputs: [wallet_output_at([])],
  }
  own_withdrawal_removed(tx, Script(a), wallet_token, a)
}

test removed_rejects_when_kept() fail {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
    outputs: [wallet_output_at([Pair(a, data)])],
  }
  own_withdrawal_removed(tx, Script(a), wallet_token, a)
}

test removed_rejects_without_wallet_input() fail {
  own_withdrawal_removed(placeholder, Script(a), wallet_token, a)
}

test removed_ignores_nft_less_decoy() fail {
  let data: Data = 0
  let decoy_output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { spenders: [], depositors: [] }),
    reference_script: None,
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
    outputs: [decoy_output, wallet_output_at([Pair(a, data)])],
  }
  own_withdrawal_removed(tx, Script(a), wallet_token, a)
}

// ------------------------------------------------------- own_depositor_data

test own_depositor_data_read_from_wallet_output() {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: nft_value(),
    datum: InlineDatum(
      WalletDatum { spenders: [], depositors: [Pair(a, data)] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  cbor.serialise(own_depositor_data(tx, Script(a), wallet_token, a)) == cbor.serialise(
    data,
  )
}

test own_depositor_data_missing_script() fail {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: nft_value(),
    datum: InlineDatum(
      WalletDatum { spenders: [], depositors: [Pair(b, data)] },
    ),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  expect _: Data = own_depositor_data(tx, Script(a), wallet_token, a)
}

test own_depositor_data_in_reads_wallet_input() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
  }
  cbor.serialise(own_depositor_data_in(tx, Script(a), wallet_token, a)) == cbor.serialise(
    data,
  )
}

// ---------------------------------------------------- own_depositor_removed

fn wallet_output_at_depositors(depositors: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(a),
    value: nft_value(),
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
  own_depositor_removed(tx, Script(a), wallet_token, a)
}

test depositor_removed_with_input_and_empty_output() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
    outputs: [wallet_output_at_depositors([])],
  }
  own_depositor_removed(tx, Script(a), wallet_token, a)
}

test depositor_removed_rejects_when_kept() fail {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
    outputs: [wallet_output_at_depositors([Pair(a, data)])],
  }
  own_depositor_removed(tx, Script(a), wallet_token, a)
}

test depositor_removed_rejects_without_wallet_input() fail {
  own_depositor_removed(placeholder, Script(a), wallet_token, a)
}

// ------------------------------------------------------ stateless data marker

test stateless_data_accepts_zero() {
  let data: Data = 0
  stateless_data_valid(data)
}

test stateless_data_rejects_nonzero() fail {
  let data: Data = 1
  stateless_data_valid(data)
}

test stateless_data_unchanged_accepts_zero() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
    outputs: [wallet_output_at([Pair(a, data)])],
  }
  own_withdrawal_stateless_unchanged(tx, Script(a), wallet_token, a)
}

test stateless_data_unchanged_rejects_rewrite() fail {
  let zero: Data = 0
  let junk: Data = 1
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, zero)])],
    outputs: [wallet_output_at([Pair(a, junk)])],
  }
  own_withdrawal_stateless_unchanged(tx, Script(a), wallet_token, a)
}

test stateless_data_unchanged_rejects_noncanonical() fail {
  let junk: Data = 1
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, junk)])],
    outputs: [wallet_output_at([Pair(a, junk)])],
  }
  own_withdrawal_stateless_unchanged(tx, Script(a), wallet_token, a)
}

test depositor_stateless_data_unchanged_accepts_zero() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
    outputs: [wallet_output_at_depositors([Pair(a, data)])],
  }
  own_depositor_stateless_unchanged(tx, Script(a), wallet_token, a)
}

test depositor_stateless_data_unchanged_rejects_rewrite() fail {
  let zero: Data = 0
  let junk: Data = 1
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, zero)])],
    outputs: [wallet_output_at_depositors([Pair(a, junk)])],
  }
  own_depositor_stateless_unchanged(tx, Script(a), wallet_token, a)
}

// ----------------------------------------------------- reference publish

fn register_certificate(credential: Credential) -> Certificate {
  RegisterCredential { credential, deposit: Never }
}

fn unregister_certificate(credential: Credential) -> Certificate {
  UnregisterCredential { credential, refund: Never }
}

fn publish_with(
  certificate: Certificate,
  tx: Transaction,
  role: withdrawal.ReferenceRole,
  register_check: fn(Data) -> Bool,
) -> Bool {
  reference_publish(
    certificate,
    tx,
    Script(a),
    wallet_token,
    role,
    register_check,
  )
}

test publish_register_spender_ok() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    outputs: [wallet_output_at([Pair(a, data)])],
  }
  publish_with(
    register_certificate(Script(a)),
    tx,
    withdrawal.Spender,
    stateless_data_valid,
  )
}

test publish_register_depositor_ok() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    outputs: [wallet_output_at_depositors([Pair(a, data)])],
  }
  publish_with(
    register_certificate(Script(a)),
    tx,
    withdrawal.Depositor,
    stateless_data_valid,
  )
}

test publish_register_rejects_failed_check() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    outputs: [wallet_output_at([Pair(a, data)])],
  }
  !publish_with(
    register_certificate(Script(a)),
    tx,
    withdrawal.Spender,
    fn(_) { False },
  )
}

test publish_register_rejects_noncanonical_data() {
  let data: Data = 1
  let tx = Transaction {
    ..placeholder,
    outputs: [wallet_output_at([Pair(a, data)])],
  }
  !publish_with(
    register_certificate(Script(a)),
    tx,
    withdrawal.Spender,
    stateless_data_valid,
  )
}

test publish_register_rejects_missing_script() fail {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    outputs: [wallet_output_at([Pair(b, data)])],
  }
  publish_with(
    register_certificate(Script(a)),
    tx,
    withdrawal.Spender,
    stateless_data_valid,
  )
}

test publish_register_rejects_key_credential() fail {
  publish_with(
    register_certificate(VerificationKey(a)),
    placeholder,
    withdrawal.Spender,
    stateless_data_valid,
  )
}

test publish_unregister_spender_ok() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
  }
  publish_with(
    unregister_certificate(Script(a)),
    tx,
    withdrawal.Spender,
    stateless_data_valid,
  )
}

test publish_unregister_depositor_ok() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at_depositors([Pair(a, data)])],
  }
  publish_with(
    unregister_certificate(Script(a)),
    tx,
    withdrawal.Depositor,
    stateless_data_valid,
  )
}

test publish_unregister_rejects_when_kept() fail {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input_at([Pair(a, data)])],
    outputs: [wallet_output_at([Pair(a, data)])],
  }
  publish_with(
    unregister_certificate(Script(a)),
    tx,
    withdrawal.Spender,
    stateless_data_valid,
  )
}

test publish_unregister_rejects_without_wallet() fail {
  publish_with(
    unregister_certificate(Script(a)),
    placeholder,
    withdrawal.Spender,
    stateless_data_valid,
  )
}

test publish_unregister_rejects_key_credential() fail {
  publish_with(
    unregister_certificate(VerificationKey(a)),
    placeholder,
    withdrawal.Spender,
    stateless_data_valid,
  )
}
