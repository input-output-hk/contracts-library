use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash, blake2b_256}
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, Value, has_any_nft, has_nft_strict}
use cardano/transaction.{
  Input, Output, OutputReference, Spend, Transaction, Withdraw,
}
use dao/types.{DaoSettings}
use settings/utils.{get_settings_datum}

/// Get the AssetName of the only token of a value under `policy`.
/// Fails unless there's exactly one (quantity == 1) Token for that policy.
pub fn get_unique_token_name(value: Value, policy: PolicyId) -> AssetName {
  expect [Pair(name, 1)] = value
    |> assets.tokens(policy)
    |> dict.to_pairs()
  name
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

/// The redeemer data attached to this script's own reward withdrawal
/// (withdraw-0 convention). Lets a script read the intent declared by whoever
/// triggered its execution.
pub fn withdraw_redeemer(self: Transaction, own_hash: ScriptHash) -> Data {
  expect Some(r) = pairs.get_first(self.redeemers, Withdraw(Script(own_hash)))
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

/// A unique Token name derived from a consumed output reference. Because an
/// output reference is spent at most once, forcing the policy to use its hashing
/// as AssetName and mint at most one of it while consuming the output in the
/// same transaction, we can generate an NFT
pub fn token_name_from_ref(ref: OutputReference) -> AssetName {
  blake2b_256(builtin.serialise_data(ref))
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

/// Read the DAO settings from the settings UTxO located by its NFT (the
/// settings token name under the settings script's own policy), casting the
/// settings contract's opaque `current` datum to `DaoSettings`.
pub fn get_dao_settings(
  self: Transaction,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) -> DaoSettings {
  let settings_datum = get_settings_datum(
    self,
    settings_policy,
    settings_token_name,
  )
  expect dao_settings: DaoSettings = settings_datum.current
  dao_settings
}
