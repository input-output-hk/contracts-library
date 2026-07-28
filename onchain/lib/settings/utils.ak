use cardano/assets.{AssetName, PolicyId, has_nft_strict}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use settings/types.{SettingsDatum}

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
