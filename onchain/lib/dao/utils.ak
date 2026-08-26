use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{blake2b_256}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId, Value, has_any_nft, has_nft_strict}
use cardano/transaction.{Input, Output, OutputReference, Spend, Transaction}
use dao/types.{DaoSettings}
use settings/utils.{get_settings_datum}

/// The single asset name held under `policy` in `value`. Fails unless there is
/// exactly one token of that policy (the NFT convention used throughout the DAO).
pub fn single_nft_name(value: Value, policy: PolicyId) -> AssetName {
  expect [Pair(name, _)] = value
    |> assets.tokens(policy)
    |> dict.to_pairs()
  name
}

/// The single mint entry under `policy` as `(name, quantity)`. Fails unless
/// exactly one token of that policy is minted or burned.
pub fn single_minted(mint: Value, policy: PolicyId) -> (AssetName, Int) {
  expect [Pair(name, quantity)] = mint
    |> assets.tokens(policy)
    |> dict.to_pairs()
  (name, quantity)
}

/// The unique continuation output at `own_addr`, if any.
pub fn find_continuation_output(
  outputs: List<Output>,
  own_addr: Address,
) -> Output {
  let out = list.expect_find(outputs, fn(o) { o.address == own_addr })
  out
}

/// The redeemer data attached to the spend of the input at `ref`. Lets one
/// script confirm that a sibling UTxO was consumed with a specific action,
/// delegating the detailed checks to that sibling's own validator.
pub fn spend_redeemer(self: Transaction, ref: OutputReference) -> Data {
  expect Some(r) = pairs.get_first(self.redeemers, Spend(ref))
  r
}

/// Locate an input holding exactly one NFT under `policy` (any name).
pub fn find_input_by_policy(inputs: List<Input>, policy: PolicyId) -> Input {
  let input = list.expect_find(
    inputs,
    fn(input) { has_any_nft(input.output.value, policy) },
  )
  input
}

/// A unique NFT name derived from a consumed output reference. Because an
/// output reference is spent at most once, hashing it yields a globally unique,
/// unforgeable token name.
pub fn nft_name_from_ref(ref: OutputReference) -> AssetName {
  blake2b_256(builtin.serialise_data(ref))
}

/// The proposal token name: a blake2b-256 hash of the creating stake UTxO's
/// output reference. This binds a proposal 1:1 to the stake position that
/// created it, so a stake position can originate at most one proposal.
pub fn proposal_token_name(stake_ref: OutputReference) -> AssetName {
  nft_name_from_ref(stake_ref)
}

/// Locate the spent proposal UTxO among the inputs by its NFT.
pub fn find_proposal_input(
  inputs: List<Input>,
  own_policy: PolicyId,
  token_name: AssetName,
) -> Input {
  let proposal_input = list.expect_find(
    inputs,
    fn(input) { has_nft_strict(input.output.value, own_policy, token_name) },
  )
  proposal_input
}

/// Read the DAO settings from the referenced settings UTxO, casting the
/// settings contract's opaque `current` datum to `DaoSettings`. The settings
/// NFT (identified by `settings_token_name` under the settings script's own
/// policy, derived from the UTxO address) must be present on the UTxO.
pub fn get_dao_settings(
  self: Transaction,
  settings_ref: OutputReference,
  settings_token_name: AssetName,
) -> DaoSettings {
  let settings_datum = get_settings_datum(
    self,
    settings_ref,
    settings_token_name,
  )
  expect dao_settings: DaoSettings = settings_datum.current
  dao_settings
}
