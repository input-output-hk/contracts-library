use cardano/assets.{PolicyId, has_nft_strict}
use cardano/address.{Credential, Script}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction, find_input}
use aiken/collection/list
use aiken/collection/dict
use authorization.{is_authorized}
use settings/types.{SettingsDatum}

pub fn validate_mint(
  seed_utxo: OutputReference,
  auth: Credential,
  out_ix: Int,
  own_policy: PolicyId,
  self: Transaction,
  validate_datum: fn(Data) -> Bool,
) {
  let Transaction { inputs, outputs, mint, .. } = self

  let correct_mint = {
    expect [Pair("settings", quantity)] =
      mint
        |> assets.tokens(own_policy)
        |> dict.to_pairs()
    quantity == 1
  }

  // seed utxo is spent
  expect Some(_) = find_input(inputs, seed_utxo)

  expect Some(settings_output) = list.at(outputs, out_ix)

  // checks for settings output
  expect Output {
    address: addr,
    value: value,
    datum: InlineDatum(datum),
    reference_script: None,
  } = settings_output

  let correct_addr = addr.payment_credential == Script(own_policy)

  let correct_value = has_nft_strict(value, own_policy, "settings")

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
