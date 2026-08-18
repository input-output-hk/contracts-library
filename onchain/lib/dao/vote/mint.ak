use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, has_nft_strict, quantity_of}
use cardano/transaction.{InlineDatum, Transaction}
use dao/types.{
  ProposalDatum, ProposalStatus, StakeRedeemer, VoteDatum, VoteProposal,
}
use dao/utils.{
  find_input_by_policy, nft_name_from_ref, single_nft_name, spend_redeemer,
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
  stake_nft_policy: PolicyId,
  stake_token_policy: PolicyId,
  stake_token_name: AssetName,
  proposal_policy: PolicyId,
  own_policy: PolicyId,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, reference_inputs, outputs, mint, .. } = self

  expect [Pair(vote_name, 1)] =
    mint
      |> assets.tokens(own_policy)
      |> dict.to_pairs()

  let stake_input = find_input_by_policy(inputs, stake_nft_policy)
  let stake_voting = {
    expect action: StakeRedeemer =
      spend_redeemer(self, stake_input.output_reference)
    action == VoteProposal
  }
  let stake =
    quantity_of(stake_input.output.value, stake_token_policy, stake_token_name)

  let proposal_ref = find_input_by_policy(reference_inputs, proposal_policy)
  let p_id = single_nft_name(proposal_ref.output.value, proposal_policy)
  let proposal_voting = {
    expect InlineDatum(d) = proposal_ref.output.datum
    expect proposal: ProposalDatum = d
    proposal.status == ProposalStatus.Voting
  }

  expect Some(vote_output) =
    list.find(
      outputs,
      fn(o) { quantity_of(o.value, own_policy, vote_name) == 1 },
    )
  expect Script(hash) = vote_output.address.payment_credential
  expect InlineDatum(vote_data) = vote_output.datum
  expect vote: VoteDatum = vote_data

  and {
    stake_voting,
    proposal_voting,
    vote_name == nft_name_from_ref(stake_input.output_reference),
    hash == own_policy,
    has_nft_strict(vote_output.value, own_policy, vote_name),
    vote_output.reference_script == None,
    vote.proposal == p_id,
    vote.stake == stake,
  }
}

/// Validate burning vote NFTs (`BurnVotes`) during a tally: every token moved
/// under `own_policy` must be a burn of exactly one.
pub fn validate_burn_votes(own_policy: PolicyId, self: Transaction) -> Bool {
  let burns =
    self.mint
      |> assets.tokens(own_policy)
      |> dict.to_pairs()
  when burns is {
    [] -> False
    _ -> list.all(burns, fn(entry) { entry.2nd == -1 })
  }
}
