use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_script}
use cardano/assets
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{InlineDatum, Output, Transaction, placeholder}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/spending_limit

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const wallet_token = "wallet"

fn nft() -> assets.Value {
  assets.from_asset(b, wallet_token, 1)
}

fn publish(certificate: Certificate, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  spending_limit.spending_limit.publish(
    Script(b),
    wallet_token,
    100,
    redeemer,
    certificate,
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

fn wallet_tx(spenders: Pairs<ScriptHash, Data>) -> Transaction {
  Transaction { ..placeholder, outputs: [wallet_output(spenders)] }
}

// ---------------------------------------------------------------- publish

test publish_register_script_credential() {
  let data: Data = 0
  let tx = wallet_tx([Pair(a, data)])
  publish(RegisterCredential { credential: Script(a), deposit: Never }, tx)
}
