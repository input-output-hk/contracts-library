use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{Finite}
use cardano/address.{Script}
use cardano/assets.{has_any_nft}
use cardano/transaction.{InlineDatum, Output, Transaction}
use dao/types.{
  CreateProposal, DaoSettings, ProposalDatum, ProposalStatus, StakeRedeemer,
}
use dao/utils.{find_proposal_input, proposal_token_name, spend_redeemer}

/// Validate the mint of a proposal NFT: the first step of creating a proposal.
///
/// Requires:
/// - exactly one token minted under `own_policy`, whose name is the hash of the
///   creating stake UTxO's output reference;
/// - that stake UTxO to be spent and to hold the staked token
///   (`staked_token_policy` / `staked_token_name`) worth at least
///   `settings.thresholds.create`;
/// - a proposal output at this script's address carrying the NFT and a valid
///   initial `ProposalDatum` (Draft status, empty results, start_time = now).
pub fn validate_create_proposal(
  settings: DaoSettings,
  staked_token_policy: assets.PolicyId,
  staked_token_name: assets.AssetName,
  own_policy: assets.PolicyId,
  out_idx: Int,
  self: Transaction,
) {
  let Transaction { inputs, outputs, mint, validity_range, .. } = self

  expect Finite(now) = validity_range.lower_bound.bound_type

  expect Some(stake_input) =
    list.find(
      inputs,
      fn(input) { has_any_nft(input.output.value, settings.stake_validator) },
    )

  let token_name = proposal_token_name(stake_input.output_reference)

  let correct_mint = {
    expect [Pair(minted_name, quantity)] =
      mint
        |> assets.tokens(own_policy)
        |> dict.to_pairs()
    quantity == 1 && minted_name == token_name
  }

  let staked_amount =
    assets.quantity_of(
      stake_input.output.value,
      staked_token_policy,
      staked_token_name,
    )

  expect staked_amount >= settings.thresholds.create

  // newly created proposal output
  expect Some(proposal_output) = list.at(outputs, out_idx)

  // The stake must be consumed with `CreateProposal`, so the stake validator
  // enforces the matching lock
  // `(token_name, now + settings.timings.draft_length, stake_amount)`.
  let stake_creating = {
    expect action: StakeRedeemer =
      spend_redeemer(self, stake_input.output_reference)
    action == CreateProposal
  }

  expect Output {
    address: addr,
    value,
    datum: InlineDatum(datum),
    reference_script: None,
  } = proposal_output

  let correct_address = addr.payment_credential == Script(own_policy)
  let correct_value = assets.has_nft_strict(value, own_policy, token_name)

  let correct_datum = {
    expect proposal_datum: ProposalDatum = datum
    let expected_datum =
      ProposalDatum {
        thresholds: settings.thresholds,
        timing_config: settings.timings,
        start_time: now,
        status: ProposalStatus.Draft { cosigning_stake: staked_amount },
        results: [],
      }

    proposal_datum == expected_datum
  }

  and {
    correct_mint,
    correct_datum,
    stake_creating,
    correct_address,
    correct_value,
  }
}

/// Validate the burning of a proposal NFT when a proposal is rejected or
/// otherwise closed. The burn must target a spent proposal UTxO under the same
/// policy and carry the exact token name that was minted for that proposal.
pub fn validate_finish_proposal(own_policy: assets.PolicyId, self: Transaction) {
  let Transaction { inputs, mint, .. } = self

  let correct_burn = {
    expect [Pair(minted_name, quantity)] =
      mint
        |> assets.tokens(own_policy)
        |> dict.to_pairs()
    quantity == -1 && {
      let proposal_input = find_proposal_input(inputs, own_policy, minted_name)
      expect Script(own_hash) = proposal_input.output.address.payment_credential
      own_hash == own_policy
    }
  }

  correct_burn
}
