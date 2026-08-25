use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, has_nft_strict, quantity_of}
use cardano/transaction.{InlineDatum, Transaction}
use dao/types.{
  ProposalDatum, ProposalStatus, StakePositionDatum, StakeRedeemer, VoteDatum,
  VoteProposal,
}
use dao/utils.{
  find_input_by_policy, nft_name_from_ref, single_minted, single_nft_name,
  spend_redeemer,
}

/// Validate minting a vote NFT (`MintVote`).
///
/// Requires the voting stake to be consumed with `VoteProposal` (so the stake
/// validator records the lock preventing a second vote), and the vote artifact
/// output to faithfully record the referenced Voting proposal and the exact
/// staked amount that will weight the vote at tally time. The vote NFT name is
/// the hash of the spent stake UTxO's output reference, so every vote is
/// globally unique (a reference is spent at most once) and the vote UTxO holds
/// nothing but its NFT and lovelace.
pub fn validate_mint_vote(
  stake_policy: PolicyId,
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  proposal_policy: PolicyId,
  own_policy: PolicyId,
  out_idx: Int,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, reference_inputs, outputs, mint, .. } = self

  expect (vote_name, 1) = single_minted(mint, own_policy)

  let stake_input = find_input_by_policy(inputs, stake_policy)

  // stake input is consumed with `VoteProposal`
  expect action: StakeRedeemer = spend_redeemer(
    self,
    stake_input.output_reference,
  )
  expect VoteProposal { voted_option } = action
  let stake = quantity_of(
    stake_input.output.value,
    staked_token_policy,
    staked_token_name,
  )
  expect InlineDatum(stake_datum) = stake_input.output.datum
  expect StakePositionDatum { owner, .. } = stake_datum

  let proposal_ref = find_input_by_policy(reference_inputs, proposal_policy)
  let p_id = single_nft_name(proposal_ref.output.value, proposal_policy)
  expect InlineDatum(proposal_data) = proposal_ref.output.datum
  expect proposal: ProposalDatum = proposal_data
  let proposal_voting = proposal.status == ProposalStatus.Voting
  let valid_option = voted_option >= 0 && voted_option < list.length(
    proposal.results,
  )

  expect Some(vote_output) = list.at(outputs, out_idx)
  expect Script(hash) = vote_output.address.payment_credential
  expect InlineDatum(vote_data) = vote_output.datum
  let expected_datum: Data = VoteDatum {
    stake_owner: owner,
    proposal: p_id,
    voted_option,
    stake,
  }

  and {
    proposal_voting,
    valid_option,
    vote_name == nft_name_from_ref(stake_input.output_reference),
    hash == own_policy,
    has_nft_strict(vote_output.value, own_policy, vote_name),
    vote_output.reference_script == None,
    expected_datum == vote_data,
  }
}

/// Validate burning vote NFTs (`BurnVotes`) during a tally: every token moved
/// under `own_policy` must be a burn of exactly one.
pub fn validate_burn_votes(own_policy: PolicyId, self: Transaction) -> Bool {
  let burns = self.mint
    |> assets.tokens(own_policy)
    |> dict.to_pairs()
  when burns is {
    [] -> False
    _ -> list.all(burns, fn(entry) { entry.2nd == -1 })
  }
}
