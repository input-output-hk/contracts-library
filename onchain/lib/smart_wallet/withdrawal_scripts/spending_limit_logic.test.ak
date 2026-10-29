use aiken/fuzz
use cardano/address.{Script, from_script}
use cardano/assets
use cardano/transaction.{
  Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/withdrawal_scripts/spending_limit_logic.{
  value_delta_below_bound, within_spending_limit,
}

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const wallet_token = "wallet"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn nft() -> assets.Value {
  assets.from_asset(wallet_policy, wallet_token, 1)
}

fn wallet_input(value: assets.Value) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: Output {
      address: from_script(wallet_policy),
      value: assets.merge(value, nft()),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn wallet_output(value: assets.Value) -> Output {
  Output {
    address: from_script(wallet_policy),
    value: assets.merge(value, nft()),
    datum: NoDatum,
    reference_script: None,
  }
}

fn stray_output(value: assets.Value) -> Output {
  Output {
    address: from_script(wallet_policy),
    value,
    datum: NoDatum,
    reference_script: None,
  }
}

// ------------------------------------------------------- value_delta_below_bound

test delta_negative_below_bound() {
  // 130 in - 100 out = 30 outflow < 50.
  value_delta_below_bound(
    assets.from_lovelace(130),
    assets.from_lovelace(100),
    50,
  )
}

test delta_at_bound_rejected() fail {
  // 150 in - 100 out = 50, not strictly < 50.
  value_delta_below_bound(
    assets.from_lovelace(150),
    assets.from_lovelace(100),
    50,
  )
}

test delta_above_bound_rejected() fail {
  // 200 in - 100 out = 100, not < 50.
  value_delta_below_bound(
    assets.from_lovelace(200),
    assets.from_lovelace(100),
    50,
  )
}

// ---------------------------------------------------- within_spending_limit

test within_limit_counts_authenticated_continuation_only() fail {
  // 98 ADA leave the authenticated wallet for an NFT-less stray output.
  Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(100_000_000))],
    outputs: [
      wallet_output(assets.from_lovelace(2_000_000)),
      stray_output(assets.from_lovelace(98_000_000)),
    ],
  }
    |> within_spending_limit(Script(wallet_policy), wallet_token, 1_000_000)
}

test within_limit_under_bound() {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(100_000_000))],
    outputs: [wallet_output(assets.from_lovelace(99_000_000))],
  }
    |> within_spending_limit(Script(wallet_policy), wallet_token, 2_000_000)
}

// --------------------------------------------------------------- properties

fn lovelace_scenario() -> Fuzzer<(Int, Int, Int)> {
  fuzz.tuple3(
    fuzz.int_between(0, 1_000_000),
    fuzz.int_between(0, 1_000_000),
    fuzz.int_between(0, 1_000_000),
  )
}

test prop_delta_below_bound((input, output, bound) via lovelace_scenario()) {
  let expected = input - output < bound
  fuzz.label_if(@"below", expected)
  fuzz.label_if(@"not-below", !expected)
  value_delta_below_bound(
    assets.from_lovelace(input),
    assets.from_lovelace(output),
    bound,
  ) == expected
}

test prop_within_spending_limit((input, output, bound) via lovelace_scenario()) {
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_input(assets.from_lovelace(input))],
    outputs: [wallet_output(assets.from_lovelace(output))],
  }
  within_spending_limit(tx, Script(wallet_policy), wallet_token, bound) == (
    input - output < bound
  )
}
