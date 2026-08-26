use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite}
use cardano/address.{Script}
use cardano/assets.{has_any_nft}
use cardano/transaction.{InlineDatum, Output, Transaction}
use dao/types.{
  CreateProposal, DaoSettings, ProposalDatum, ProposalStatus, StakeRedeemer,
}
use dao/utils.{proposal_token_name, single_minted, spend_redeemer}

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
  results: List<ScriptHash>,
  self: Transaction,
) {
  let Transaction { inputs, outputs, mint, validity_range, .. } = self

  expect Finite(now) = validity_range.lower_bound.bound_type

  // The stake position is matched loosely (any NFT under the stake policy);
  // its own spend validator re-checks the detailed constraints on that input.
  let stake_input = list.expect_find(
    inputs,
    fn(input) { has_any_nft(input.output.value, settings.stake_validator) },
  )

  let token_name = proposal_token_name(stake_input.output_reference)

  let correct_mint = {
    let (minted_name, quantity) = single_minted(mint, own_policy)
    quantity == 1 && minted_name == token_name
  }

  let staked_amount = assets.quantity_of(
    stake_input.output.value,
    staked_token_policy,
    staked_token_name,
  )

  expect staked_amount >= settings.thresholds.create

  let proposal_output = list.expect_at(outputs, out_idx)

  // The stake must be consumed with `CreateProposal`, so the stake validator
  // enforces the matching lock
  // `(token_name, now + settings.timings.draft_length, stake_amount)`.
  let stake_creating = {
    expect action: StakeRedeemer = spend_redeemer(
      self,
      stake_input.output_reference,
    )
    action == CreateProposal
  }

  expect  
      Output {
        address: addr,
        value,
        datum: InlineDatum(datum),
        reference_script: None,
      }
    = proposal_output

  let correct_address = addr.payment_credential == Script(own_policy)
  let correct_value = assets.has_nft_strict(value, own_policy, token_name)

  let correct_datum = {
    let expected_datum: Data = ProposalDatum {
      thresholds: settings.thresholds,
      timing_config: settings.timings,
      start_time: now,
      status: ProposalStatus.Draft { cosigning_stake: staked_amount },
      results,
    }

    datum == expected_datum
  }

  and {
    correct_mint,
    correct_datum,
    stake_creating,
    correct_address,
    correct_value,
  }
}

/// Validate the burning of proposal NFTs when proposals are rejected or
/// otherwise closed. The spend branches check their own input NFT being
/// burned, with exact policy and unique name.
pub fn validate_finish_proposal(own_policy: assets.PolicyId, self: Transaction) {
  let burns = self.mint
    |> assets.tokens(own_policy)
    |> dict.to_pairs()
  and {
    list.length(burns) > 0,
    list.all(burns, fn(entry) { entry.2nd == -1 }),
  }
}
