use aiken/collection/list
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{OutputReference, Transaction}
use dao/types.{ProposalRedeemer, TallyVotes, VoteDatum, VoteRedeemer}
use dao/utils.{spend_redeemer}

/// Spending logic for a vote artifact UTxO.
///
/// A vote is only ever consumed as part of tallying its proposal. We require
/// the matching proposal UTxO to be spent with `TallyVotes`, delegating vote
/// counting, ADA refunds, and NFT burning to the proposal validator.
pub fn validate_vote_spend(
  proposal_policy: PolicyId,
  datum: VoteDatum,
  _redeemer: VoteRedeemer,
  _own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, .. } = self
  expect Some(proposal_input) =
    list.find(
      inputs,
      fn(i) {
        quantity_of(i.output.value, proposal_policy, datum.proposal) == 1
      },
    )
  expect action: ProposalRedeemer =
    spend_redeemer(self, proposal_input.output_reference)
  action == TallyVotes
}
