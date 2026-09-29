use aiken/crypto.{ScriptHash}
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet
use smart_wallet/types.{WalletDatum}

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn publish(certificate: Certificate, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  smart_wallet.spending_limit.publish(Script(b), 100, redeemer, certificate, tx)
}

fn wallet_output(withdrawals: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(b),
    value: assets.zero,
    datum: InlineDatum(
      WalletDatum { withdrawals, depositor: VerificationKey(a) },
    ),
    reference_script: None,
  }
}

fn wallet_input(withdrawals: Pairs<ScriptHash, Data>) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
    output: wallet_output(withdrawals),
  }
}

fn wallet_tx(withdrawals: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction { ..placeholder, outputs: [wallet_output(withdrawals)] }
}

fn removal_tx(withdrawals: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(withdrawals)],
    outputs: [wallet_output([])],
  }
}

fn kept_tx(withdrawals: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input(withdrawals)],
    outputs: [wallet_output(withdrawals)],
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
