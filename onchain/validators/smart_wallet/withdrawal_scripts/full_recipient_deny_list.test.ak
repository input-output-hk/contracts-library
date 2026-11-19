use aiken/crypto.{ScriptHash}
use cardano/address.{
  Address, Script, VerificationKey, from_script, from_verification_key,
}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/full_recipient_deny_list

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const recipient = #"33333333333333333333333333333333333333333333333333333333"

const stranger = #"44444444444444444444444444444444444444444444444444444444"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const wallet_token = "wallet"

fn nft() -> assets.Value {
  assets.from_asset(b, wallet_token, 1)
}

fn denied() -> List<Address> {
  [from_verification_key(recipient)]
}

fn publish(certificate: Certificate, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  full_recipient_deny_list.full_recipient_deny_list.publish(
    Script(b),
    wallet_token,
    denied(),
    redeemer,
    certificate,
    tx,
  )
}

fn withdraw(denied: List<Address>, tx: Transaction) -> Bool {
  full_recipient_deny_list.full_recipient_deny_list.withdraw(
    Script(b),
    wallet_token,
    denied,
    0,
    Script(a),
    tx,
  )
}

fn wallet_output(spenders: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(b),
    value: nft(),
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

fn wallet_tx(spenders: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(spenders)],
    outputs: [wallet_output(spenders)],
  }
}

fn removal_tx(spenders: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(spenders)],
    outputs: [wallet_output([])],
  }
}

fn kept_tx(spenders: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(spenders)],
    outputs: [wallet_output(spenders)],
  }
}

fn payout(address: Address) -> Output {
  Output {
    address,
    value: assets.from_lovelace(1_000_000),
    datum: NoDatum,
    reference_script: None,
  }
}

fn spend_tx(address: Address) -> Transaction {
  let data: Data = 0
  Transaction {
    ..placeholder,
    inputs: [wallet_input([Pair(a, data)])],
    outputs: [wallet_output([Pair(a, data)]), payout(address)],
  }
}

// ---------------------------------------------------------------- publish

test publish_register_script_credential() {
  let data: Data = 0
  let tx = wallet_tx([Pair(a, data)])
  publish(RegisterCredential { credential: Script(a), deposit: Never }, tx)
}

test publish_rejects_register_not_listed() fail {
  let data: Data = 0
  let tx = wallet_tx([Pair(a, data)])
  publish(RegisterCredential { credential: Script(b), deposit: Never }, tx)
}

test publish_rejects_key_credential() fail {
  publish(
    RegisterCredential { credential: VerificationKey(a), deposit: Never },
    placeholder,
  )
}

test publish_accepts_unregister_on_removal() {
  let data: Data = 0
  publish(
    UnregisterCredential { credential: Script(a), refund: Never },
    removal_tx([Pair(a, data)]),
  )
}

test publish_rejects_unregister_without_wallet() fail {
  publish(
    UnregisterCredential { credential: Script(a), refund: Never },
    placeholder,
  )
}

test publish_rejects_unregister_when_kept() fail {
  let data: Data = 0
  publish(
    UnregisterCredential { credential: Script(a), refund: Never },
    kept_tx([Pair(a, data)]),
  )
}

test publish_rejects_key_credential_unregister() fail {
  publish(
    UnregisterCredential { credential: VerificationKey(a), refund: Never },
    placeholder,
  )
}

// ---------------------------------------------------------------- withdraw

test withdraw_allows_unlisted_recipient() {
  withdraw(denied(), spend_tx(from_verification_key(stranger)))
}

test withdraw_rejects_denied_recipient() fail {
  withdraw(denied(), spend_tx(from_verification_key(recipient)))
}

test withdraw_empty_deny_list_allows_any_recipient() {
  withdraw([], spend_tx(from_verification_key(recipient)))
}

test withdraw_exempts_wallet_address() {
  let data: Data = 0
  withdraw([from_script(b)], wallet_tx([Pair(a, data)]))
}
