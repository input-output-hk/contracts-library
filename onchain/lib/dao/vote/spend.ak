use authorization.{is_authorized}
use cardano/address.{Script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{OutputReference, Transaction, find_input}
use dao/types.{
  Cancel, ProposalRedeemer, TallyVote, TallyVotes, VoteDatum, VoteRedeemer,
}
use dao/utils.{find_proposal_input, single_nft_name, spend_redeemer}

/// Spending logic for a vote artifact UTxO.
///
/// A vote is normally consumed as part of tallying its proposal: we require
/// the matching proposal UTxO to be spent with `TallyVotes` (delegating vote
/// counting, ADA refunds, and NFT burning to the proposal validator). The
/// stake owner may instead `Cancel` their vote at any time before that,
/// unconditionally, as long as the vote's own NFT is burned rather than
/// carried into an output.
pub fn validate_vote_spend(
  proposal_policy: PolicyId,
  datum: VoteDatum,
  redeemer: VoteRedeemer,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { mint, inputs, extra_signatories, withdrawals, .. } = self

  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let own_nft = single_nft_name(own_input.output.value, own_hash)
  let nft_burned = quantity_of(mint, own_hash, own_nft) == -1

  when redeemer is {
    TallyVote -> {
      let proposal_input = find_proposal_input(
        inputs,
        proposal_policy,
        datum.proposal,
      )
      expect Script(policy) = proposal_input.output.address.payment_credential

      let tallied = {
        expect action: ProposalRedeemer = spend_redeemer(
          self,
          proposal_input.output_reference,
        )
        action == TallyVotes
      }

      and {
        tallied,
        policy == proposal_policy,
        nft_burned,
      }
    }
    Cancel -> and {
        is_authorized(datum.stake_owner, extra_signatories, withdrawals),
        nft_burned,
      }
  }
}
