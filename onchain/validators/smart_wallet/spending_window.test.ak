use aiken/crypto.{ScriptHash}
use aiken/interval
use cardano/address.{Credential, Script, from_script}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/spending_window
use smart_wallet/spending_window_logic.{SpendingWindowState}
use smart_wallet/types.{WalletDatum}

const a = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const window = 3_600_000

fn wallet_output(withdrawals: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(wallet_policy),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { withdrawals, depositor: Script(a) }),
    reference_script: None,
  }
}

fn wallet_input(withdrawals: Pairs<ScriptHash, Data>) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output(withdrawals),
  }
}

fn publish(redeemer: Data, certificate: Certificate, tx: Transaction) -> Bool {
  spending_window.spending_window.publish(
    Script(wallet_policy),
    window,
    redeemer,
    certificate,
    tx,
  )
}

fn withdraw(account: Credential, tx: Transaction) -> Bool {
  spending_window.spending_window.withdraw(
    Script(wallet_policy),
    window,
    0,
    account,
    tx,
  )
}

// ---------------------------------------------------------------- publish

test publish_register_valid_initial_state() {
  let data: Data = SpendingWindowState { last_spend: 0 }
  publish(
    0,
    RegisterCredential { credential: Script(a), deposit: Never },
    Transaction { ..placeholder, outputs: [wallet_output([Pair(a, data)])] },
  )
}

test publish_register_rejects_bad_initial() fail {
  let data: Data = SpendingWindowState { last_spend: 500 }
  publish(
    0,
    RegisterCredential { credential: Script(a), deposit: Never },
    Transaction { ..placeholder, outputs: [wallet_output([Pair(a, data)])] },
  )
}

test publish_unregister_on_removal() {
  let data: Data = SpendingWindowState { last_spend: 500 }
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(a, data)])],
    outputs: [wallet_output([])],
  }
  publish(0, UnregisterCredential { credential: Script(a), refund: Never }, tx)
}

test publish_unregister_rejects_when_kept() fail {
  let data: Data = SpendingWindowState { last_spend: 500 }
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(a, data)])],
    outputs: [wallet_output([Pair(a, data)])],
  }
  publish(0, UnregisterCredential { credential: Script(a), refund: Never }, tx)
}

// ---------------------------------------------------------------- withdraw

test withdraw_first_spend() {
  let current: Data = SpendingWindowState { last_spend: 0 }
  let next: Data = SpendingWindowState { last_spend: 1000 }
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(a, current)])],
    outputs: [wallet_output([Pair(a, next)])],
    validity_range: interval.after(1000),
  }
  withdraw(Script(a), tx)
}

test withdraw_rejects_cooldown() fail {
  let current: Data = SpendingWindowState { last_spend: 500 }
  let next: Data = SpendingWindowState { last_spend: 3_000_000 }
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(a, current)])],
    outputs: [wallet_output([Pair(a, next)])],
    validity_range: interval.after(3_000_000),
  }
  withdraw(Script(a), tx)
}
