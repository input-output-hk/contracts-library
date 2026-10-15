use aiken/crypto.{ScriptHash}
use aiken/interval
use cardano/address.{Script, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/spending_window_logic.{
  SpendingWindowState, initial_state_valid, validate_withdraw,
}

const own_hash = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const window = 3_600_000

fn wallet_output(spenders: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(wallet_policy),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { spenders, depositors: [] }),
    reference_script: None,
  }
}

fn wallet_input(spenders: Pairs<ScriptHash, Data>) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output(spenders),
  }
}

fn spend_tx(
  current: SpendingWindowState,
  next: SpendingWindowState,
  now: Int,
) -> Transaction {
  let cur: Data = current
  let nxt: Data = next
  Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(own_hash, cur)])],
    outputs: [wallet_output([Pair(own_hash, nxt)])],
    validity_range: interval.after(now),
  }
}

fn validate(tx: Transaction) -> Bool {
  validate_withdraw(tx, Script(wallet_policy), own_hash, window)
}

// ------------------------------------------------------- initial_state_valid

test initial_state_zero_valid() {
  initial_state_valid(state(0))
}

test initial_state_rejects_nonzero() fail {
  initial_state_valid(state(500))
}

// ----------------------------------------------------------- validate_withdraw

test first_spend_allowed() {
  validate(
    spend_tx(
      SpendingWindowState { last_spend: 0 },
      SpendingWindowState { last_spend: 1000 },
      1000,
    ),
  )
}

test cooldown_elapsed_allowed() {
  validate(
    spend_tx(
      SpendingWindowState { last_spend: 500 },
      SpendingWindowState { last_spend: 3_600_500 },
      3_600_500,
    ),
  )
}

test cooldown_not_elapsed_rejected() fail {
  validate(
    spend_tx(
      SpendingWindowState { last_spend: 500 },
      SpendingWindowState { last_spend: 3_000_000 },
      3_000_000,
    ),
  )
}

test wrong_next_state_rejected() fail {
  validate(
    spend_tx(
      SpendingWindowState { last_spend: 500 },
      SpendingWindowState { last_spend: 3_600_500 },
      3_600_400,
    ),
  )
}

fn state(last_spend: Int) -> Data {
  let state: Data = SpendingWindowState { last_spend }
  state
}
