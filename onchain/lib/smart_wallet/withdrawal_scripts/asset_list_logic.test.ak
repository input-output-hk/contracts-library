use aiken/fuzz
use cardano/address.{Script, from_script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/fuzz as cardano_fuzz
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

const wallet_token = "wallet"

fn nft() -> Value {
  assets.from_asset(wallet_policy, wallet_token, 1)
}

fn wallet_input(value: Value) -> Input {
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

fn wallet_output(value: Value) -> Output {
  Output {
    address: from_script(wallet_policy),
    value: assets.merge(value, nft()),
    datum: NoDatum,
    reference_script: None,
  }
}

/// An NFT-less output at the wallet address: not authenticated wallet value.
fn stray_output(value: Value) -> Output {
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
    wallet_token,
    allow_any(policy_a),
  )
}

test allow_listed_policy_listed_name() {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    allow_only(policy_a, [name_x]),
  )
}

test allow_rejects_unlisted_policy() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_b),
  )
}

test allow_rejects_unlisted_name() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    allow_only(policy_a, [name_y]),
  )
}

test allow_rejects_partial_move_of_unlisted() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 4)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_b),
  )
}

test allow_ignores_unchanged_holding() {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 10)),
    Script(wallet_policy),
    wallet_token,
    none(),
  )
}

test allow_rejects_added_asset() fail {
  only_allowed_assets_moved(
    tx(lovelace(2_000_000), holding(policy_a, name_x, 5)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_b),
  )
}

test allow_empty_list_rejects_any_move() fail {
  only_allowed_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    none(),
  )
}

test allow_ignores_lovelace_only_change() {
  only_allowed_assets_moved(
    tx(lovelace(2_000_000), lovelace(1_500_000)),
    Script(wallet_policy),
    wallet_token,
    none(),
  )
}

test allow_deposit_listed() {
  only_allowed_assets_moved(
    tx(lovelace(2_000_000), holding(policy_a, name_x, 5)),
    Script(wallet_policy),
    wallet_token,
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
    wallet_token,
    none(),
  )
}

test allow_ignores_stray_when_authenticated_value_unchanged() {
  let authentic = holding(policy_a, name_x, 10)
  let stray = lovelace(2_000_000) |> assets.add(policy_b, name_y, 5)
  Transaction {
    ..placeholder,
    inputs: [wallet_input(authentic)],
    outputs: [wallet_output(authentic), stray_output(stray)],
  }
    |> only_allowed_assets_moved(Script(wallet_policy), wallet_token, none())
}

test allow_rejects_move_hidden_in_stray_output() fail {
  let input = holding(policy_a, name_x, 10)
  let stray = lovelace(2_000_000) |> assets.add(policy_a, name_x, 10)
  Transaction {
    ..placeholder,
    inputs: [wallet_input(input)],
    outputs: [wallet_output(lovelace(2_000_000)), stray_output(stray)],
  }
    |> only_allowed_assets_moved(Script(wallet_policy), wallet_token, none())
}

// -------------------------------------------------- no_denied_assets_moved

test deny_rejects_denied_policy_any_name() fail {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_a),
  )
}

test deny_rejects_denied_name() fail {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    allow_only(policy_a, [name_x]),
  )
}

test deny_allows_other_name_same_policy() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    allow_only(policy_a, [name_y]),
  )
}

test deny_rejects_partial_move() fail {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 4)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_a),
  )
}

test deny_allows_unlisted_policy() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_b),
  )
}

test deny_ignores_unchanged_holding() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), holding(policy_a, name_x, 10)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_a),
  )
}

test deny_empty_list_allows_all() {
  no_denied_assets_moved(
    tx(holding(policy_a, name_x, 10), lovelace(2_000_000)),
    Script(wallet_policy),
    wallet_token,
    none(),
  )
}

test deny_rejects_added_asset() fail {
  no_denied_assets_moved(
    tx(lovelace(2_000_000), holding(policy_a, name_x, 5)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_a),
  )
}

test deny_ignores_lovelace_only_change() {
  no_denied_assets_moved(
    tx(lovelace(2_000_000), lovelace(1_500_000)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy_a),
  )
}

// --------------------------------------------------------------- properties

fn asset_scenario() -> Fuzzer<(PolicyId, AssetName, Int, Int)> {
  fuzz.and_then(
    fuzz.such_that(
      cardano_fuzz.policy_id(),
      fn(policy) { policy != wallet_policy },
    ),
    fn(policy) {
      fuzz.and_then(
        cardano_fuzz.asset_name(),
        fn(name) {
          fuzz.and_then(
            fuzz.int_between(1, 1_000),
            fn(qty_in) {
              fuzz.map(
                fuzz.int_between(0, 1_000),
                fn(qty_out) { (policy, name, qty_in, qty_out) },
              )
            },
          )
        },
      )
    },
  )
}

test prop_allow_empty_iff_unchanged(
  (policy, name, qty_in, qty_out) via asset_scenario(),
) {
  let accepted = only_allowed_assets_moved(
    tx(holding(policy, name, qty_in), holding(policy, name, qty_out)),
    Script(wallet_policy),
    wallet_token,
    none(),
  )
  fuzz.label_if(@"moving", qty_in != qty_out)
  fuzz.label_if(@"unchanged", qty_in == qty_out)
  accepted == ( qty_in == qty_out )
}

test prop_allow_listed_policy_accepts(
  (policy, name, qty_in, qty_out) via asset_scenario(),
) {
  only_allowed_assets_moved(
    tx(holding(policy, name, qty_in), holding(policy, name, qty_out)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy),
  )
}

test prop_deny_listed_policy_iff_unchanged(
  (policy, name, qty_in, qty_out) via asset_scenario(),
) {
  let accepted = no_denied_assets_moved(
    tx(holding(policy, name, qty_in), holding(policy, name, qty_out)),
    Script(wallet_policy),
    wallet_token,
    allow_any(policy),
  )
  accepted == ( qty_in == qty_out )
}
