use aiken/crypto.{ScriptHash}
use cardano/address.{
  Address, Credential, Script, VerificationKey, from_script,
  from_verification_key, with_delegation_key,
}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/payment_staking_allow_list

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const payer = #"33333333333333333333333333333333333333333333333333333333"

const staker = #"44444444444444444444444444444444444444444444444444444444"

const stranger = #"55555555555555555555555555555555555555555555555555555555"

const stranger_stake =
  #"66666666666666666666666666666666666666666666666666666666"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn allowed_payments() -> List<Credential> {
  [VerificationKey(payer)]
}

fn allowed_stakings() -> List<Credential> {
  [VerificationKey(staker)]
}

fn publish(certificate: Certificate, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  payment_staking_allow_list.payment_staking_allow_list.publish(
    Script(b),
    allowed_payments(),
    allowed_stakings(),
    redeemer,
    certificate,
    tx,
  )
}

fn withdraw(
  allowed_payments: List<Credential>,
  allowed_stakings: List<Credential>,
  tx: Transaction,
) -> Bool {
  payment_staking_allow_list.payment_staking_allow_list.withdraw(
    Script(b),
    allowed_payments,
    allowed_stakings,
    0,
    Script(a),
    tx,
  )
}

fn wallet_output(spenders: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(b),
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

fn wallet_tx(spenders: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction { ..placeholder, outputs: [wallet_output(spenders)] }
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
    outputs: [wallet_output([Pair(a, data)]), payout(address)],
  }
}

fn staked_recipient() -> Address {
  with_delegation_key(from_verification_key(payer), staker)
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

test withdraw_allows_listed_payment_and_staking() {
  withdraw(allowed_payments(), allowed_stakings(), spend_tx(staked_recipient()))
}

test withdraw_rejects_unlisted_staking() fail {
  withdraw(
    allowed_payments(),
    allowed_stakings(),
    spend_tx(with_delegation_key(from_verification_key(payer), stranger_stake)),
  )
}

test withdraw_rejects_unlisted_payment() fail {
  withdraw(
    allowed_payments(),
    allowed_stakings(),
    spend_tx(with_delegation_key(from_verification_key(stranger), staker)),
  )
}

test withdraw_rejects_missing_staking_credential() fail {
  withdraw(
    allowed_payments(),
    allowed_stakings(),
    spend_tx(from_verification_key(payer)),
  )
}

test withdraw_empty_allowed_stakings_permits_any_staking() {
  withdraw(
    allowed_payments(),
    [],
    spend_tx(with_delegation_key(from_verification_key(payer), stranger_stake)),
  )
}

test withdraw_empty_allowed_payments_permits_any_payment() {
  withdraw(
    [],
    allowed_stakings(),
    spend_tx(with_delegation_key(from_verification_key(stranger), staker)),
  )
}
