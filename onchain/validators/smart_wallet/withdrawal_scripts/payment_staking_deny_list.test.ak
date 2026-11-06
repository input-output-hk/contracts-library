use aiken/crypto.{ScriptHash}
use cardano/address.{
  Address, Credential, Script, VerificationKey, from_script,
  from_verification_key, with_delegation_key,
}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/payment_staking_deny_list

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const payer = #"33333333333333333333333333333333333333333333333333333333"

const staker = #"44444444444444444444444444444444444444444444444444444444"

const stranger = #"55555555555555555555555555555555555555555555555555555555"

const stranger_stake =
  #"66666666666666666666666666666666666666666666666666666666"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const wallet_token = "wallet"

fn nft() -> assets.Value {
  assets.from_asset(b, wallet_token, 1)
}

fn denied_payments() -> List<Credential> {
  [VerificationKey(payer)]
}

fn denied_stakings() -> List<Credential> {
  [VerificationKey(staker)]
}

fn publish(certificate: Certificate, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  payment_staking_deny_list.payment_staking_deny_list.publish(
    Script(b),
    wallet_token,
    denied_payments(),
    denied_stakings(),
    redeemer,
    certificate,
    tx,
  )
}

fn withdraw(
  denied_payments: List<Credential>,
  denied_stakings: List<Credential>,
  tx: Transaction,
) -> Bool {
  payment_staking_deny_list.payment_staking_deny_list.withdraw(
    Script(b),
    wallet_token,
    denied_payments,
    denied_stakings,
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

// ---------------------------------------------------------------- withdraw

test withdraw_allows_unlisted_payment_and_staking() {
  withdraw(
    denied_payments(),
    denied_stakings(),
    spend_tx(from_verification_key(stranger)),
  )
}

test withdraw_rejects_denied_payment() fail {
  withdraw(
    denied_payments(),
    denied_stakings(),
    spend_tx(from_verification_key(payer)),
  )
}

test withdraw_rejects_denied_staking() fail {
  withdraw(
    denied_payments(),
    denied_stakings(),
    spend_tx(with_delegation_key(from_verification_key(stranger), staker)),
  )
}

test withdraw_empty_denied_payments_permits_any_payment() {
  withdraw(
    [],
    denied_stakings(),
    spend_tx(with_delegation_key(from_verification_key(payer), stranger_stake)),
  )
}

test withdraw_empty_denied_stakings_permits_any_staking() {
  withdraw(
    denied_payments(),
    [],
    spend_tx(with_delegation_key(from_verification_key(stranger), staker)),
  )
}

test withdraw_empty_lists_permit_all() {
  withdraw(
    [],
    [],
    spend_tx(with_delegation_key(from_verification_key(payer), staker)),
  )
}

test withdraw_exempts_wallet_address() {
  let data: Data = 0
  withdraw([Script(b)], [], wallet_tx([Pair(a, data)]))
}
