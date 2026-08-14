use aiken/collection/dict
use aiken/interval.{Finite}
use cardano/address.{Script}
use cardano/assets
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
use dao/types.{CreateProposal, ProposalDatum, ProposalStatus, StakeRedeemer}
use dao/utils.{
  find_proposal_input, find_proposal_output, find_stake_input, get_dao_settings,
  proposal_token_name, spend_redeemer,
}

/// Validate the mint of a proposal NFT: the first step of creating a proposal.
///
/// Requires:
/// - exactly one token minted under `own_policy`, whose name is the hash of the
///   creating stake UTxO's output reference;
/// - that stake UTxO to be spent and to hold `stake_token` worth at least
///   `thresholds.create`;
/// - the referenced settings UTxO to supply the thresholds/timings the proposal
///   copies into its datum;
/// - a proposal output at this script's address carrying the NFT and a valid
///   initial `ProposalDatum` (Draft status, empty results, start_time = now).
pub fn validate_create_proposal(
  settings_utxo: OutputReference,
  stake_nft_policy: assets.PolicyId,
  stake_nft_name: assets.AssetName,
  stake_token_policy: assets.PolicyId,
  stake_token_name: assets.AssetName,
  settings_token_name: assets.AssetName,
  own_policy: assets.PolicyId,
  self: Transaction,
) {
  let Transaction { inputs, outputs, mint, validity_range, .. } = self

  expect Finite(now) = validity_range.lower_bound.bound_type

  let stake_input = find_stake_input(inputs, stake_nft_policy, stake_nft_name)
  let token_name = proposal_token_name(stake_input.output_reference)

  let correct_mint = {
    expect [Pair(minted_name, quantity)] =
      mint
        |> assets.tokens(own_policy)
        |> dict.to_pairs()
    quantity == 1 && minted_name == token_name
  }

  let stake_amount =
    assets.quantity_of(
      stake_input.output.value,
      stake_token_policy,
      stake_token_name,
    )

  let settings = get_dao_settings(self, settings_utxo, settings_token_name)

  expect stake_amount >= settings.thresholds.create

  let proposal_output = find_proposal_output(outputs, own_policy, token_name)

  // The stake must be consumed with `CreateProposal`, so the stake validator
  // enforces the matching lock `(token_name, now + draft_length, stake_amount)`.
  let stake_creating = {
    expect action: StakeRedeemer =
      spend_redeemer(self, stake_input.output_reference)
    action == CreateProposal
  }

  let correct_datum = {
    expect Output {
      address: addr,
      value,
      datum: InlineDatum(datum),
      reference_script: None,
    } = proposal_output

    expect addr.payment_credential == Script(own_policy)
    expect assets.has_nft_strict(value, own_policy, token_name)

    expect proposal_datum: ProposalDatum = datum

    let expected_datum =
      ProposalDatum {
        thresholds: settings.thresholds,
        timing_config: settings.timings,
        start_time: now,
        status: ProposalStatus.Draft { cosigning_stake: stake_amount },
        results: [],
      }

    proposal_datum == expected_datum
  }

  and {
    correct_mint,
    correct_datum,
    stake_creating,
  }
}

/// Validate the burning of a proposal NFT when a proposal is rejected or
/// otherwise closed. The burn must target a spent proposal UTxO under the same
/// policy and carry the exact token name that was minted for that proposal.
pub fn validate_finish_proposal(
  own_policy: assets.PolicyId,
  self: Transaction,
) {
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
