use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_script}
use cardano/assets.{Value}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/checks.{validate_deposit}
use smart_wallet/types.{WalletDatum}

const wallet_policy =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_token = "WALLET"

const deposit_script =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const other_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn wallet_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 0 }
}

fn wallet_datum() -> WalletDatum {
  WalletDatum { spenders: [], depositors: [] }
}

fn wallet_datum_with(depositors: Pairs<ScriptHash, Data>) -> WalletDatum {
  WalletDatum { spenders: [], depositors }
}

fn wallet_input() -> Input {
  wallet_input_with(wallet_datum())
}

fn wallet_input_with(datum: WalletDatum) -> Input {
  Input {
    output_reference: wallet_ref(),
    output: Output {
      address: from_script(wallet_policy),
      value: assets.from_lovelace(1_000_000)
        |> assets.add(wallet_policy, wallet_token, 1),
      datum: InlineDatum(datum),
      reference_script: None,
    },
  }
}

fn wallet_output(value: Value) -> Output {
  wallet_output_with(value, wallet_datum())
}

fn wallet_output_with(value: Value, datum: WalletDatum) -> Output {
  Output {
    address: from_script(wallet_policy),
    value,
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn deposit(tx: Transaction) -> Bool {
  validate_deposit(0, wallet_ref(), tx)
}

// ---------------------------------------------------------------- deposit

test deposit_ok_open_depositors() {
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
    |> assets.add(other_policy, "SOME", 5)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output(cont_value)],
    },
  )
}

test deposit_ok_with_invoked_depositor() {
  let data: Data = 0
  let datum = wallet_datum_with([Pair(deposit_script, data)])
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input_with(datum)],
      outputs: [wallet_output_with(cont_value, datum)],
      withdrawals: [Pair(Script(deposit_script), 0)],
    },
  )
}

test rejects_deposit_missing_depositor_withdrawal() fail {
  let data: Data = 0
  let datum = wallet_datum_with([Pair(deposit_script, data)])
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input_with(datum)],
      outputs: [wallet_output_with(cont_value, datum)],
    },
  )
}

test rejects_deposit_removing_funds() fail {
  let cont_value = assets.from_lovelace(500_000)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output(cont_value)],
    },
  )
}

test rejects_deposit_missing_nft() fail {
  let cont_value = assets.from_lovelace(1_500_000)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output(cont_value)],
    },
  )
}

test rejects_deposit_changing_spenders() fail {
  let data: Data = 0
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  let bad_datum = WalletDatum {
    spenders: [Pair(deposit_script, data)],
    depositors: [],
  }
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output_with(cont_value, bad_datum)],
    },
  )
}

test rejects_deposit_changing_depositors() fail {
  let data: Data = 0
  let other_data: Data = 1
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  let in_datum = wallet_datum_with([Pair(deposit_script, data)])
  let bad_datum = wallet_datum_with([Pair(deposit_script, other_data)])
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input_with(in_datum)],
      outputs: [wallet_output_with(cont_value, bad_datum)],
      withdrawals: [Pair(Script(deposit_script), 0)],
    },
  )
}

test rejects_deposit_wrong_address() fail {
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  let bad_output = Output {
    address: from_script(other_policy),
    value: cont_value,
    datum: InlineDatum(wallet_datum()),
    reference_script: None,
  }
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [bad_output],
    },
  )
}
