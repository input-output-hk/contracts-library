use cardano/address.{VerificationKey, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use smart_wallet/checks.{validate_close}
use smart_wallet/types.{WalletDatum}

const wallet_policy =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_token = "WALLET"

const admin_vkh = #"11111111111111111111111111111111111111111111111111111111"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn wallet_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 0 }
}

fn wallet_input() -> Input {
  Input {
    output_reference: wallet_ref(),
    output: Output {
      address: from_script(wallet_policy),
      value: assets.from_lovelace(1_000_000)
        |> assets.add(wallet_policy, wallet_token, 1),
      datum: InlineDatum(WalletDatum { withdrawals: [] }),
      reference_script: None,
    },
  }
}

fn close_tx() -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [wallet_input()],
    mint: assets.from_asset(wallet_policy, wallet_token, -1),
    extra_signatories: [admin_vkh],
  }
}

fn close(tx: Transaction) -> Bool {
  validate_close(VerificationKey(admin_vkh), wallet_ref(), tx)
}

// -------------------------------------------------------------- close

test close_ok() {
  close(close_tx())
}

test rejects_close_unsigned() fail {
  close(Transaction { ..close_tx(), extra_signatories: [] })
}

test rejects_close_without_burn() fail {
  close(Transaction { ..close_tx(), mint: assets.zero })
}

test rejects_close_with_mint_instead_of_burn() fail {
  close(
    Transaction {
      ..close_tx(),
      mint: assets.from_asset(wallet_policy, wallet_token, 1),
    },
  )
}

test rejects_close_missing_wallet_input() fail {
  close(Transaction { ..close_tx(), inputs: [] })
}
