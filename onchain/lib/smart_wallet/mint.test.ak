use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder,
}
use smart_wallet/mint.{validate_burn, validate_mint}
use smart_wallet/types.{WalletDatum}

const wallet_policy =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const wallet_token = "WALLET"

const other_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const admin_vkh = #"11111111111111111111111111111111111111111111111111111111"

const seed_tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn seed_ref() -> OutputReference {
  OutputReference { transaction_id: seed_tx_id, output_index: 0 }
}

fn seed_input() -> Input {
  Input {
    output_reference: seed_ref(),
    output: Output {
      address: from_script(other_policy),
      value: assets.from_lovelace(1),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn wallet_datum() -> WalletDatum {
  WalletDatum { withdrawals: [] }
}

fn wallet_output() -> Output {
  Output {
    address: from_script(wallet_policy),
    value: assets.from_lovelace(1_000_000)
      |> assets.add(wallet_policy, wallet_token, 1),
    datum: InlineDatum(wallet_datum()),
    reference_script: None,
  }
}

fn mint_tx() -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [seed_input()],
    outputs: [wallet_output()],
    mint: assets.from_asset(wallet_policy, wallet_token, 1),
    extra_signatories: [admin_vkh],
  }
}

fn mint(tx: Transaction) -> Bool {
  validate_mint(
    seed_ref(),
    0,
    wallet_policy,
    wallet_token,
    VerificationKey(admin_vkh),
    tx,
  )
}

fn burn_tx() -> Transaction {
  Transaction {
    ..placeholder,
    mint: assets.from_asset(wallet_policy, wallet_token, -1),
  }
}

fn burn(tx: Transaction) -> Bool {
  validate_burn(wallet_policy, tx)
}

// ------------------------------------------------------------- mint happy path

test mint_ok() {
  mint(mint_tx())
}

// ----------------------------------------------------------- mint adversarial

test rejects_wrong_token_name() fail {
  mint(
    Transaction { ..mint_tx(), mint: assets.from_asset(wallet_policy, "X", 1) },
  )
}

test rejects_wrong_mint_quantity() fail {
  mint(
    Transaction {
      ..mint_tx(),
      mint: assets.from_asset(wallet_policy, wallet_token, 2),
    },
  )
}

test rejects_missing_seed_input() fail {
  mint(Transaction { ..mint_tx(), inputs: [] })
}

test rejects_missing_nft_in_output() fail {
  let bad_output = Output {
    ..wallet_output(),
    value: assets.from_lovelace(1_000_000),
  }
  mint(Transaction { ..mint_tx(), outputs: [bad_output] })
}

test rejects_non_empty_withdrawals() fail {
  let bad_output = Output {
    ..wallet_output(),
    datum: InlineDatum(WalletDatum { withdrawals: [Script(other_policy)] }),
  }
  mint(Transaction { ..mint_tx(), outputs: [bad_output] })
}

test rejects_wrong_address() fail {
  let bad_output = Output {
    ..wallet_output(),
    address: from_script(other_policy),
  }
  mint(Transaction { ..mint_tx(), outputs: [bad_output] })
}

test rejects_reference_script() fail {
  let bad_output = Output {
    ..wallet_output(),
    reference_script: Some(other_policy),
  }
  mint(Transaction { ..mint_tx(), outputs: [bad_output] })
}

test rejects_datum_hash_output() fail {
  let bad_output = Output { ..wallet_output(), datum: DatumHash(seed_tx_id) }
  mint(Transaction { ..mint_tx(), outputs: [bad_output] })
}

test rejects_mint_unsigned() fail {
  mint(Transaction { ..mint_tx(), extra_signatories: [] })
}

// --------------------------------------------------------------- burn

test burn_ok() {
  burn(burn_tx())
}

test rejects_burn_wrong_quantity() fail {
  burn(
    Transaction {
      ..burn_tx(),
      mint: assets.from_asset(wallet_policy, wallet_token, -2),
    },
  )
}

test rejects_burn_wrong_direction() fail {
  burn(
    Transaction {
      ..burn_tx(),
      mint: assets.from_asset(wallet_policy, wallet_token, 1),
    },
  )
}
