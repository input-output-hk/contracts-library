use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/asset_deposit_deny_list

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const policy_x = #"33333333333333333333333333333333333333333333333333333333"

const policy_y = #"44444444444444444444444444444444444444444444444444444444"

const token = "TOKEN"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const wallet_token = "wallet"

fn nft() -> assets.Value {
  assets.from_asset(b, wallet_token, 1)
}

fn wallet_value(value: assets.Value) -> assets.Value {
  assets.merge(value, nft())
}

fn denied() -> Pairs<PolicyId, List<AssetName>> {
  let names: List<AssetName> = []
  [Pair(policy_x, names)]
}

fn publish(certificate: Certificate, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  asset_deposit_deny_list.asset_deposit_deny_list.publish(
    Script(b),
    wallet_token,
    denied(),
    redeemer,
    certificate,
    tx,
  )
}

fn withdraw(denied: Pairs<PolicyId, List<AssetName>>, tx: Transaction) -> Bool {
  asset_deposit_deny_list.asset_deposit_deny_list.withdraw(
    Script(b),
    wallet_token,
    denied,
    0,
    Script(a),
    tx,
  )
}

fn wallet_output(value: Value, depositors: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(b),
    value: wallet_value(value),
    datum: InlineDatum(WalletDatum { spenders: [], depositors }),
    reference_script: None,
  }
}

fn wallet_input(value: Value, depositors: Pairs<ScriptHash, Data>) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output(value, depositors),
  }
}

fn wallet_tx(depositors: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction {
    ..placeholder,
    outputs: [wallet_output(assets.zero, depositors)],
  }
}

fn lovelace(quantity: Int) -> Value {
  assets.from_lovelace(quantity)
}

fn holding(policy: PolicyId, name: AssetName, quantity: Int) -> Value {
  assets.from_lovelace(2_000_000) |> assets.add(policy, name, quantity)
}

fn deposit_tx(input: Value, output: Value) -> Transaction {
  let data: Data = 0
  Transaction {
    ..placeholder,
    inputs: [wallet_input(input, [Pair(a, data)])],
    outputs: [wallet_output(output, [Pair(a, data)])],
  }
}

// ---------------------------------------------------------------- publish

test publish_register_script_credential() {
  let data: Data = 0
  let tx = wallet_tx([Pair(a, data)])
  publish(RegisterCredential { credential: Script(a), deposit: Never }, tx)
}

// ---------------------------------------------------------------- withdraw

test withdraw_rejects_denied_deposit() fail {
  withdraw(
    denied(),
    deposit_tx(lovelace(2_000_000), holding(policy_x, token, 5)),
  )
}

test withdraw_allows_unlisted_deposit() {
  withdraw(
    denied(),
    deposit_tx(lovelace(2_000_000), holding(policy_y, token, 5)),
  )
}

test withdraw_empty_list_allows_deposit() {
  withdraw([], deposit_tx(lovelace(2_000_000), holding(policy_x, token, 5)))
}
