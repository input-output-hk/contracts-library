use aiken/crypto.{ScriptHash}
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{InlineDatum, Output, Transaction, placeholder}
use smart_wallet
use smart_wallet/types.{WalletDatum}

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

fn publish(certificate: Certificate, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  smart_wallet.spending_limit.publish(Script(b), 100, redeemer, certificate, tx)
}

fn wallet_output(withdrawals: Pairs<ScriptHash, Data>) -> Output {
  Output {
    address: from_script(b),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { withdrawals }),
    reference_script: None,
  }
}

fn wallet_tx(withdrawals: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction { ..placeholder, outputs: [wallet_output(withdrawals)] }
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

test publish_accepts_unregister() {
  publish(
    UnregisterCredential { credential: Script(a), refund: Never },
    placeholder,
  )
}

test publish_rejects_key_credential_unregister() fail {
  publish(
    UnregisterCredential { credential: VerificationKey(a), refund: Never },
    placeholder,
  )
}
