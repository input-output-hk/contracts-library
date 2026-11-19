use aiken/interval
use cardano/address.{Script, from_script}
use cardano/assets.{Value}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/spending_period_limit_logic.{
  SpendingPeriodState, initial_state_valid, params_valid, validate_withdraw,
}

const own_hash = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const interval_ms = 1_000

const max_spend = 100

const wallet_token = "wallet"

fn nft() -> Value {
  assets.from_asset(wallet_policy, wallet_token, 1)
}

fn wallet_value(value: Value) -> Value {
  assets.merge(value, nft())
}

fn wallet_output(value: Value, period_state: SpendingPeriodState) -> Output {
  Output {
    address: from_script(wallet_policy),
    value: wallet_value(value),
    datum: InlineDatum(
      WalletDatum {
        spenders: [Pair(own_hash, state_data(period_state))],
        depositors: [],
      },
    ),
    reference_script: None,
  }
}

fn wallet_input(value: Value, period_state: SpendingPeriodState) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output(value, period_state),
  }
}

fn spend_tx_with(
  input: Int,
  output: Int,
  validity_range: interval.Interval,
  current: SpendingPeriodState,
  next: SpendingPeriodState,
) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(input), current)],
    outputs: [wallet_output(assets.from_lovelace(output), next)],
    validity_range,
  }
}

fn validate_tx(tx: Transaction) -> Bool {
  validate_withdraw(
    tx,
    Script(wallet_policy),
    wallet_token,
    own_hash,
    interval_ms,
    max_spend,
  )
}

fn validate(
  input: Int,
  output: Int,
  at: Int,
  current: SpendingPeriodState,
  next: SpendingPeriodState,
) -> Bool {
  validate_tx(
    spend_tx_with(input, output, interval.between(at, at), current, next),
  )
}

fn validate_range(
  input: Int,
  output: Int,
  lower: Int,
  upper: Int,
  current: SpendingPeriodState,
  next: SpendingPeriodState,
) -> Bool {
  validate_tx(
    spend_tx_with(input, output, interval.between(lower, upper), current, next),
  )
}

fn state(period: Int, acc_spend: Int) -> SpendingPeriodState {
  SpendingPeriodState { period, acc_spend }
}

fn state_data(s: SpendingPeriodState) -> Data {
  let d: Data = s
  d
}

// ------------------------------------------------------- initial_state_valid

test initial_state_zero_valid() {
  initial_state_valid(state_data(state(0, 0)))
}

test initial_state_rejects_nonzero_period() fail {
  initial_state_valid(state_data(state(1, 0)))
}

test initial_state_rejects_nonzero_spend() fail {
  initial_state_valid(state_data(state(0, 1)))
}

// -------------------------------------------------------------- params_valid

test params_accept_valid() {
  params_valid(interval_ms, 0)
}

test params_reject_zero_interval() fail {
  params_valid(0, max_spend)
}

test params_reject_negative_interval() fail {
  params_valid(-1, max_spend)
}

test params_reject_negative_max_spend() fail {
  params_valid(interval_ms, -1)
}

// ------------------------------------------------------------ same period

test same_period_under_cap() {
  // tx_spend 40; 30 + 40 = 70 <= 100.
  validate(100, 60, 1500, state(2000, 30), state(2000, 70))
}

test same_period_at_cap() {
  // 60 + 40 = 100 <= 100 (inclusive).
  validate(100, 60, 1500, state(2000, 60), state(2000, 100))
}

test same_period_over_cap_rejected() fail {
  // 61 + 40 = 101 > 100.
  validate(100, 60, 1500, state(2000, 61), state(2000, 101))
}

test lower_at_period_end_starts_next_period() {
  // `[start, end)`: 2000 belongs to the period ending at 3000.
  validate(100, 60, 2000, state(2000, 30), state(3000, 40))
}

test same_period_wrong_next_rejected() fail {
  validate(100, 60, 1500, state(2000, 30), state(2000, 71))
}

test same_period_zero_outflow_unchanged() {
  validate(100, 100, 1500, state(2000, 30), state(2000, 30))
}

// --------------------------------------------------------------- rollover

test rollover_under_cap() {
  // 2500 is in the period ending at 3000; accumulator restarts at tx_spend.
  validate(100, 60, 2500, state(2000, 30), state(3000, 40))
}

test rollover_resets_accumulator() {
  // The previous accumulator (90) is discarded, not carried over.
  validate(100, 60, 2500, state(2000, 90), state(3000, 40))
}

test rollover_at_cap() {
  validate(100, 0, 2500, state(2000, 0), state(3000, 100))
}

test rollover_over_cap_rejected() fail {
  validate(101, 0, 2500, state(2000, 0), state(3000, 101))
}

test rollover_wrong_period_rejected() fail {
  // Next period must be the fixed-grid boundary (3000), not the old one.
  validate(100, 60, 2500, state(2000, 30), state(2000, 40))
}

test first_spend_from_zero_period() {
  validate(100, 60, 1500, state(0, 0), state(2000, 40))
}

test rollover_zero_outflow_advances_period() {
  validate(100, 100, 2500, state(0, 0), state(3000, 0))
}

// -------------------------------------------------------- validity interval

test interval_spanning_periods_rejected() fail {
  validate_range(100, 60, 1500, 2500, state(2000, 30), state(3000, 40))
}

test historical_period_rejected() fail {
  validate_range(100, 60, 500, 999, state(2000, 0), state(1000, 40))
}

test exclusive_upper_at_period_end_allowed() {
  validate_tx(
    spend_tx_with(
      100,
      60,
      interval.entirely_between(1500, 2000),
      state(2000, 30),
      state(2000, 70),
    ),
  )
}

test inclusive_upper_at_period_end_rejected() fail {
  validate_range(100, 60, 1500, 2000, state(2000, 30), state(2000, 70))
}

test infinite_upper_rejected() fail {
  validate_tx(
    spend_tx_with(
      100,
      60,
      interval.after(1500),
      state(2000, 30),
      state(2000, 70),
    ),
  )
}

test stray_output_does_not_hide_outflow() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(100), state(2000, 30))],
    outputs: [
      wallet_output(assets.from_lovelace(60), state(2000, 30)),
      Output {
        address: from_script(wallet_policy),
        value: assets.from_lovelace(40),
        datum: NoDatum,
        reference_script: None,
      },
    ],
    validity_range: interval.between(1500, 1999),
  }
  validate_tx(tx)
}

test infinite_lower_rejected() fail {
  validate_tx(
    spend_tx_with(
      100,
      60,
      interval.before(1999),
      state(2000, 30),
      state(2000, 70),
    ),
  )
}
