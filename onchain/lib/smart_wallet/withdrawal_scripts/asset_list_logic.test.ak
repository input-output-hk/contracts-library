use cardano/address.{Script, from_script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{
  Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/withdrawal_scripts/asset_list_logic.{
  no_denied_assets_moved, only_allowed_assets_moved,
}

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const policy_a = #"11111111111111111111111111111111111111111111111111111111"

const policy_b = #"22222222222222222222222222222222222222222222222222222222"

const name_x = "X"

const name_y = "Y"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn wallet_input(value: Value) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: Output {
      address: from_script(wallet_policy),
      value,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn wallet_output(value: Value) -> Output {
  Output {
    address: from_script(wallet_policy),
    value,
    datum: NoDatum,
    reference_script: None,
  }
}

fn tx(input: Value, output: Value) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(input)],
    outputs: [wallet_output(output)],
  }
}

fn lovelace(quantity: Int) -> Value {
  assets.from_lovelace(quantity)
}

fn holding(policy: PolicyId, name: AssetName, quantity: Int) -> Value {
  assets.from_lovelace(2_000_000) |> assets.add(policy, name, quantity)
}

fn none() -> Pairs<PolicyId, List<AssetName>> {
  []
}

/// A policy listed with an empty name list (all of its names).
fn allow_any(policy: PolicyId) -> Pairs<PolicyId, List<AssetName>> {
  let names: List<AssetName> = []
  [Pair(policy, names)]
}

/// A policy listed with specific names.
fn allow_only(
  policy: PolicyId,
  names: List<AssetName>,
) -> Pairs<PolicyId, List<AssetName>> {
  [Pair(policy, names)]
}

// ------------------------------------------------- only_allowed_assets_moved

test allow_listed_policy_any_name() {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_any(policy_a),
  )
}

test allow_listed_policy_listed_name() {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_only(policy_a, [name_x]),
  )
}

test allow_rejects_unlisted_policy() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_any(policy_b),
  )
}

test allow_rejects_unlisted_name() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_only(policy_a, [name_y]),
  )
}

test allow_rejects_partial_move_of_unlisted() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 4)),
    Script(wallet_policy),
    allow_any(policy_b),
  )
}

test allow_ignores_unchanged_holding() {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 10)),
    Script(wallet_policy),
    none(),
  )
}

test allow_rejects_added_asset() fail {
  only_allowed_assets_moved(
    tx(lovelace(2_000_000), holding(policy_a, name_x, 5)),
    Script(wallet_policy),
    allow_any(policy_b),
  )
}

test allow_empty_list_rejects_any_move() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    none(),
  )
}

test allow_ignores_lovelace_only_change() {
  only_allowed_assets_moved(
    tx(lovelace(2_000_000), lovelace(1_500_000)),
    Script(wallet_policy),
    none(),
  )
}

test allow_deposit_listed() {
  only_allowed_assets_moved(
    tx(lovelace(2_000_000), holding(policy_a, name_x, 5)),
    Script(wallet_policy),
    allow_any(policy_a),
  )
}

test allow_ignores_non_wallet_outputs() {
  only_allowed_assets_moved(
    Transaction {
      ..placeholder,
      inputs: [wallet_input(holding(policy_a, name_x, 10))],
      outputs: [
        wallet_output(holding(policy_a, name_x, 10)),
        Output {
          address: from_script(policy_b),
          value: holding(policy_a, name_x, 3),
          datum: NoDatum,
          reference_script: None,
        },
      ],
    },
    Script(wallet_policy),
    none(),
  )
}

// -------------------------------------------------- no_denied_assets_moved

test deny_rejects_denied_policy_any_name() fail {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_any(policy_a),
  )
}

test deny_rejects_denied_name() fail {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_only(policy_a, [name_x]),
  )
}

test deny_allows_other_name_same_policy() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_only(policy_a, [name_y]),
  )
}

test deny_rejects_partial_move() fail {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 4)),
    Script(wallet_policy),
    allow_any(policy_a),
  )
}

test deny_allows_unlisted_policy() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    allow_any(policy_b),
  )
}

test deny_ignores_unchanged_holding() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 10)),
    Script(wallet_policy),
    allow_any(policy_a),
  )
}

test deny_empty_list_allows_all() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    none(),
  )
}

test deny_rejects_added_asset() fail {
  no_denied_assets_moved(
    tx(lovelace(2_000_000), holding(policy_a, name_x, 5)),
    Script(wallet_policy),
    allow_any(policy_a),
  )
}

test deny_ignores_lovelace_only_change() {
  no_denied_assets_moved(
    tx(lovelace(2_000_000), lovelace(1_500_000)),
    Script(wallet_policy),
    allow_any(policy_a),
  )
}
