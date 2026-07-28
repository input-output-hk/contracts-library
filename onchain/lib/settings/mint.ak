use aiken/collection/dict
use aiken/collection/list
use authorization.{is_authorized}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId, has_nft_strict}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_input,
}
use settings/types.{SettingsDatum}

pub fn validate_mint(
  seed_utxo: OutputReference,
  auth: Credential,
  out_ix: Int,
  own_policy: PolicyId,
  self: Transaction,
  settings_token_name: AssetName,
  validate_datum: fn(Data) -> Bool,
) {
  let Transaction { inputs, outputs, mint, .. } = self

  let correct_mint = {
    expect [Pair(minted_token_name, quantity)] =
      mint
        |> assets.tokens(own_policy)
        |> dict.to_pairs()
    quantity == 1 && minted_token_name == settings_token_name
  }

  // seed utxo is spent
  expect Some(_) = find_input(inputs, seed_utxo)

  expect Some(settings_output) = list.at(outputs, out_ix)

  // checks for settings output
  expect Output {
    address: addr,
    value,
    datum: InlineDatum(datum),
    reference_script: None,
  } = settings_output

  let correct_addr = addr.payment_credential == Script(own_policy)

  let correct_value = has_nft_strict(value, own_policy, settings_token_name)

  let correct_datum = {
    expect SettingsDatum { current, next, next_apply } = datum
    and {
      validate_datum(current),
      next == None,
      next_apply == None,
    }
  }
  and {
    is_authorized(auth, self.extra_signatories, self.withdrawals),
    correct_mint,
    correct_addr,
    correct_value,
    correct_datum,
  }
}

pub fn validate_burn(auth: Credential, own_policy: PolicyId, self: Transaction) {
  let Transaction { mint, .. } = self

  let correct_burn = {
    expect [Pair(_, quantity)] =
      mint
        |> assets.tokens(own_policy)
        |> dict.to_pairs()
    quantity == -1
  }

  and {
    is_authorized(auth, self.extra_signatories, self.withdrawals),
    correct_burn,
  }
}
