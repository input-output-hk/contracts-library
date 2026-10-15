use aiken/crypto.{ScriptHash}
use aiken/interval
use cardano/address.{Credential, Script, from_script}
use cardano/assets.{Value}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/spending_period_limit
use smart_wallet/withdrawal_scripts/spending_period_limit_logic.{
  SpendingPeriodState,
}

const a = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const interval_ms = 1_000

const max_spend = 100

fn state(period: Int, acc_spend: Int) -> SpendingPeriodState {
  SpendingPeriodState { period, acc_spend }
}

fn state_data(s: SpendingPeriodState) -> Data {
  let d: Data = s
  d
}

fn wallet_output_with(value: Value, spenders: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(wallet_policy),
    value,
    datum: InlineDatum(WalletDatum { spenders, depositors: [] }),
    reference_script: None,
  }
}

fn wallet_output(value: Value, period_state: SpendingPeriodState) -> Output {
  wallet_output_with(value, [Pair(a, state_data(period_state))])
}

fn wallet_input_with(value: Value, spenders: Pairs<ScriptHash, Data>) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output_with(value, spenders),
  }
}

fn wallet_input(value: Value, period_state: SpendingPeriodState) -> Input {
  wallet_input_with(value, [Pair(a, state_data(period_state))])
}

fn publish(redeemer: Data, certificate: Certificate, tx: Transaction) -> Bool {
  spending_period_limit.spending_period_limit.publish(
    Script(wallet_policy),
    interval_ms,
    max_spend,
    redeemer,
    certificate,
    tx,
  )
}

fn withdraw(account: Credential, tx: Transaction) -> Bool {
  spending_period_limit.spending_period_limit.withdraw(
    Script(wallet_policy),
    interval_ms,
    max_spend,
    0,
    account,
    tx,
  )
}

// ---------------------------------------------------------------- publish

test publish_register_valid_initial_state() {
  publish(
    0,
    RegisterCredential { credential: Script(a), deposit: Never },
    Transaction {
      ..placeholder,
      outputs: [wallet_output(assets.zero, state(0, 0))],
    },
  )
}

test publish_register_rejects_bad_initial() fail {
  publish(
    0,
    RegisterCredential { credential: Script(a), deposit: Never },
    Transaction {
      ..placeholder,
      outputs: [wallet_output(assets.zero, state(0, 5))],
    },
  )
}

test publish_unregister_on_removal() {
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.zero, state(0, 5))],
    outputs: [wallet_output_with(assets.zero, [])],
  }
  publish(0, UnregisterCredential { credential: Script(a), refund: Never }, tx)
}

test publish_unregister_rejects_when_kept() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.zero, state(0, 5))],
    outputs: [wallet_output(assets.zero, state(0, 5))],
  }
  publish(0, UnregisterCredential { credential: Script(a), refund: Never }, tx)
}

// --------------------------------------------------------------- withdraw

test withdraw_same_period_under_cap() {
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(100), state(2000, 30))],
    outputs: [wallet_output(assets.from_lovelace(60), state(2000, 70))],
    validity_range: interval.after(1500),
  }
  withdraw(Script(a), tx)
}

test withdraw_rollover_resets() {
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(100), state(2000, 90))],
    outputs: [wallet_output(assets.from_lovelace(60), state(3000, 40))],
    validity_range: interval.after(2500),
  }
  withdraw(Script(a), tx)
}

test withdraw_over_cap_rejected() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(100), state(2000, 61))],
    outputs: [wallet_output(assets.from_lovelace(60), state(2000, 101))],
    validity_range: interval.after(1500),
  }
  withdraw(Script(a), tx)
}
