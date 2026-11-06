use aiken/crypto.{ScriptHash}
use aiken/fuzz
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

const wallet_token = "wallet"

fn wallet_value() -> assets.Value {
  assets.from_asset(wallet_policy, wallet_token, 1)
}

fn wallet_output(spenders: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(wallet_policy),
    value: wallet_value(),
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
  lower: Int,
  upper: Int,
) -> Transaction {
  let cur: Data = current
  let nxt: Data = next
  Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(own_hash, cur)])],
    outputs: [wallet_output([Pair(own_hash, nxt)])],
    validity_range: interval.between(lower, upper),
  }
}

fn validate(tx: Transaction) -> Bool {
  validate_withdraw(tx, Script(wallet_policy), wallet_token, own_hash, window)
}

// ------------------------------------------------------- initial_state_valid

test initial_state_zero_valid() {
  initial_state_valid(state(0))
}

// ----------------------------------------------------------- validate_withdraw

test first_spend_allowed() {
  validate(
    spend_tx(
      SpendingWindowState { last_upper: 0 },
      SpendingWindowState { last_upper: 2000 },
      1000,
      2000,
    ),
  )
}

test cooldown_elapsed_allowed() {
  validate(
    spend_tx(
      SpendingWindowState { last_upper: 500 },
      SpendingWindowState { last_upper: 3_700_000 },
      3_600_500,
      3_700_000,
    ),
  )
}

test backdated_first_spend_allowed() {
  validate(
    spend_tx(
      SpendingWindowState { last_upper: window },
      SpendingWindowState { last_upper: 3 * window + 1_000 },
      2 * window,
      3 * window + 1_000,
    ),
  )
}

test backdated_lower_rejected() fail {
  validate(
    spend_tx(
      SpendingWindowState { last_upper: 3_600_500 },
      SpendingWindowState { last_upper: 3_600_600 },
      3_600_000,
      3_600_600,
    ),
  )
}

test infinite_upper_rejected() fail {
  let current: Data = SpendingWindowState { last_upper: 0 }
  let next: Data = SpendingWindowState { last_upper: 1000 }
  Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(own_hash, current)])],
    outputs: [wallet_output([Pair(own_hash, next)])],
    validity_range: interval.after(1000),
  }
    |> validate
}

test infinite_lower_rejected() fail {
  let current: Data = SpendingWindowState { last_upper: 0 }
  let next: Data = SpendingWindowState { last_upper: 1000 }
  Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(own_hash, current)])],
    outputs: [wallet_output([Pair(own_hash, next)])],
    validity_range: interval.before(1000),
  }
    |> validate
}

fn state(last_upper: Int) -> Data {
  let state: Data = SpendingWindowState { last_upper }
  state
}

// --------------------------------------------------------------- properties

fn validate_with_window(tx: Transaction, window_value: Int) -> Bool {
  validate_withdraw(
    tx,
    Script(wallet_policy),
    wallet_token,
    own_hash,
    window_value,
  )
}

test prop_window_initial_state(last_upper via fuzz.int()) {
  initial_state_valid(state(last_upper)) == ( last_upper == 0 )
}

fn window_scenario() -> Fuzzer<(Int, Int, Int, Int, Int)> {
  fuzz.tuple5(
    fuzz.int_between(0, 10_000_000),
    fuzz.int_between(0, 10_000_000),
    fuzz.int_between(0, 1_000_000),
    fuzz.int_between(0, 5_000_000),
    fuzz.int_between(0, 10_000_000),
  )
}

test prop_window_rule(
  (last_upper, lower, upper_delta, window_value, next_upper) via window_scenario(),
) {
  let upper = lower + upper_delta
  let tx = spend_tx(
    SpendingWindowState { last_upper },
    SpendingWindowState { last_upper: next_upper },
    lower,
    upper,
  )
  let expected = ( last_upper == 0 || lower - last_upper >= window_value ) && next_upper == upper
  fuzz.label_if(@"accepted", expected)
  fuzz.label_if(@"rejected", !expected)
  validate_with_window(tx, window_value) == expected
}
