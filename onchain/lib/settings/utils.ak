use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, has_nft_strict}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}
use settings/types.{SettingsDatum}

/// Extract a SettingsDatum from a reference input that holds the
/// settings NFT.
pub fn get_settings_datum(
  self: Transaction,
  settings_ref: OutputReference,
  policy: PolicyId,
  token_name: AssetName,
) -> SettingsDatum {
  let Transaction { reference_inputs, .. } = self
  expect Some(settings_input) = find_input(reference_inputs, settings_ref)
  expect has_nft_strict(settings_input.output.value, policy, token_name)
  expect InlineDatum(datum) = settings_input.output.datum
  expect settings_datum: SettingsDatum = datum
  settings_datum
}

/// Validate a continuation output for propose/apply operations.
///
/// Finds the own input, gets the script hash, locates the
/// continuation output at `out_ix`, and checks that it has the
/// correct address, the settings NFT, an inline datum, and no
/// reference script. Returns the raw datum for the caller to cast.
pub fn expect_continuation(
  inputs: List<Input>,
  outputs: List<Output>,
  own_ref: OutputReference,
  out_ix: Int,
  settings_token_name: AssetName,
) -> Data {
  expect Some(cont_output) = list.at(outputs, out_ix)
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential

  expect  
      Output {
        address: cont_addr,
        value,
        datum: InlineDatum(cont_datum),
        reference_script: None,
      }
    = cont_output

  expect cont_addr == own_input.output.address
  expect has_nft_strict(value, own_hash, settings_token_name)

  cont_datum
}
