use cardano/address.{VerificationKey, from_script}
use cardano/assets.{Value}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/checks.{validate_deposit}
use smart_wallet/types.{WalletDatum}

const wallet_policy =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_token = "WALLET"

const depositor_vkh =
  #"11111111111111111111111111111111111111111111111111111111"

const other_vkh = #"22222222222222222222222222222222222222222222222222222222"

const other_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn wallet_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 0 }
}

fn wallet_datum() -> WalletDatum {
  WalletDatum { withdrawals: [], depositor: VerificationKey(depositor_vkh) }
}

fn wallet_input() -> Input {
  Input {
    output_reference: wallet_ref(),
    output: Output {
      address: from_script(wallet_policy),
      value: assets.from_lovelace(1_000_000)
        |> assets.add(wallet_policy, wallet_token, 1),
      datum: InlineDatum(wallet_datum()),
      reference_script: None,
    },
  }
}

fn wallet_output(value: Value) -> Output {
  Output {
    address: from_script(wallet_policy),
    value,
    datum: InlineDatum(wallet_datum()),
    reference_script: None,
  }
}

fn deposit(tx: Transaction) -> Bool {
  validate_deposit(0, wallet_ref(), tx)
}

// ---------------------------------------------------------------- deposit

test deposit_ok() {
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
    |> assets.add(other_policy, "SOME", 5)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output(cont_value)],
      extra_signatories: [depositor_vkh],
    },
  )
}

test rejects_deposit_unsigned() fail {
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output(cont_value)],
    },
  )
}

test rejects_deposit_removing_funds() fail {
  let cont_value = assets.from_lovelace(500_000)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output(cont_value)],
      extra_signatories: [depositor_vkh],
    },
  )
}

test rejects_deposit_missing_nft() fail {
  let cont_value = assets.from_lovelace(1_500_000)
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [wallet_output(cont_value)],
      extra_signatories: [depositor_vkh],
    },
  )
}

test rejects_deposit_changing_datum() fail {
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  let bad_output = Output {
    address: from_script(wallet_policy),
    value: cont_value,
    datum: InlineDatum(
      WalletDatum { withdrawals: [], depositor: VerificationKey(other_vkh) },
    ),
    reference_script: None,
  }
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [bad_output],
      extra_signatories: [depositor_vkh],
    },
  )
}

test rejects_deposit_wrong_address() fail {
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  let bad_output = Output {
    address: from_script(other_policy),
    value: cont_value,
    datum: InlineDatum(wallet_datum()),
    reference_script: None,
  }
  deposit(
    Transaction {
      ..placeholder,
      inputs: [wallet_input()],
      outputs: [bad_output],
      extra_signatories: [depositor_vkh],
    },
  )
}
