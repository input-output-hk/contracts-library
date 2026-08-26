use authorization.{is_authorized}
use cardano/address.{Script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{OutputReference, Transaction, find_input}
use dao/types.{ProposalRedeemer, TallyVotes, VoteDatum}
use dao/utils.{find_proposal_input, single_nft_name, spend_redeemer}

/// Spending logic for a vote artifact UTxO.
///
/// A vote is normally consumed as part of tallying its proposal: we require
/// the matching proposal UTxO to be spent with `TallyVotes` (delegating vote
/// counting, ADA refunds, and NFT burning to the proposal validator). The
/// stake owner may instead `Cancel` their vote at any time before that,
/// unconditionally, as long as the vote's own NFT is burned rather than
/// carried into an output. The validator wrapper dispatches the redeemer to
/// the matching function below.
/// Whether the vote's own NFT is burned in this transaction.
fn nft_burned(self: Transaction, own_ref: OutputReference) -> Bool {
  let Transaction { inputs, mint, .. } = self
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let own_nft = single_nft_name(own_input.output.value, own_hash)
  quantity_of(mint, own_hash, own_nft) == -1
}

pub fn validate_vote_tally(
  proposal_policy: PolicyId,
  datum: VoteDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, .. } = self
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
    nft_burned(self, own_ref),
  }
}

pub fn validate_vote_cancel(
  datum: VoteDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { extra_signatories, withdrawals, .. } = self
  and {
    is_authorized(datum.stake_owner, extra_signatories, withdrawals),
    nft_burned(self, own_ref),
  }
}
