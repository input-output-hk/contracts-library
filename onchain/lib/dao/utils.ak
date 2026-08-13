use aiken/builtin
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/assets.{AssetName, PolicyId, has_nft}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}
use dao/types.{DaoSettings}
use settings/types as settings_types

/// The proposal token name: a blake2b-256 hash of the creating stake UTxO's
/// output reference. This binds a proposal 1:1 to the stake position that
/// created it, so a stake position can originate at most one proposal.
pub fn proposal_token_name(stake_ref: OutputReference) -> AssetName {
  blake2b_256(builtin.serialise_data(stake_ref))
}

/// Locate the stake UTxO among the spent inputs by its NFT.
pub fn find_stake_input(
  inputs: List<Input>,
  stake_nft_policy: PolicyId,
  stake_nft_name: AssetName,
) -> Input {
  expect Some(stake_input) =
    list.find(
      inputs,
      fn(input) {
        has_nft(input.output.value, stake_nft_policy, stake_nft_name)
      },
    )
  stake_input
}

/// Locate the proposal output among the transaction outputs by its NFT.
pub fn find_proposal_output(
  outputs: List<Output>,
  own_policy: PolicyId,
  token_name: AssetName,
) -> Output {
  expect Some(proposal_output) =
    list.find(
      outputs,
      fn(output) { has_nft(output.value, own_policy, token_name) },
    )
  proposal_output
}

/// Read the DAO settings from the referenced settings UTxO, casting the
/// settings contract's opaque `current` datum to `DaoSettings`.
pub fn get_dao_settings(
  self: Transaction,
  settings_ref: OutputReference,
) -> DaoSettings {
  let Transaction { reference_inputs, .. } = self
  expect Some(settings_input) = find_input(reference_inputs, settings_ref)
  expect InlineDatum(datum) = settings_input.output.datum
  expect settings_datum: settings_types.SettingsDatum = datum
  expect dao_settings: DaoSettings = settings_datum.current
  dao_settings
}
