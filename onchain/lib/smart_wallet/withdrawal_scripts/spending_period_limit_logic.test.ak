use aiken/interval
use cardano/address.{Script, from_script}
use cardano/assets.{Value}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/spending_period_limit_logic.{
  SpendingPeriodState, initial_state_valid, validate_withdraw,
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

fn spend_tx(
  input: Int,
  output: Int,
  now: Int,
  current: SpendingPeriodState,
  next: SpendingPeriodState,
) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(input), current)],
    outputs: [wallet_output(assets.from_lovelace(output), next)],
    validity_range: interval.after(now),
  }
}

fn validate(
  input: Int,
  output: Int,
  now: Int,
  current: SpendingPeriodState,
  next: SpendingPeriodState,
) -> Bool {
  validate_withdraw(
    spend_tx(input, output, now, current, next),
    Script(wallet_policy),
    wallet_token,
    own_hash,
    interval_ms,
    max_spend,
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

test boundary_now_equals_period_is_same_period() {
  // `now <= period`: at the exact boundary it is still the current period.
  validate(100, 60, 2000, state(2000, 30), state(2000, 70))
}

test same_period_wrong_next_rejected() fail {
  validate(100, 60, 1500, state(2000, 30), state(2000, 71))
}

test same_period_zero_outflow_unchanged() {
  validate(100, 100, 1500, state(2000, 30), state(2000, 30))
}

// --------------------------------------------------------------- rollover

test rollover_under_cap() {
  // now 2500 > 2000 -> next boundary 3000, accumulator restarts at tx_spend.
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
