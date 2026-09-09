use aiken/collection/list
use authorization.{is_authorized}
use cardano/address.{Script}
use cardano/assets.{PolicyId, from_lovelace, lovelace_of, quantity_of}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_input, resolve_input,
}
use dao/types.{ProposalRedeemer, TallyVotes, VoteDatum}
use dao/utils.{find_proposal_input, get_unique_token_name, spend_redeemer}

/// Spending logic for a vote artifact UTxO.
///
/// A vote is normally consumed as part of tallying its proposal: we require
/// the matching proposal UTxO to be spent with `TallyVotes` (which counts the
/// votes and burns the NFTs) and a refund output declared by our `out_idx`
/// redeemer field: tagged with the vote's own output reference as inline
/// datum, paid to the vote's recorded `stake_owner`, holding **at least** the
/// vote UTxO's lovelace and nothing but lovelace. The stake owner may instead
/// `Cancel` their vote at any time before that, unconditionally, as long as
/// the vote's own NFT is burned rather than carried into an output. The
/// validator wrapper dispatches the redeemer to the matching function below.
/// Whether the vote's own NFT is burned in this transaction.
fn nft_burned(self: Transaction, own_ref: OutputReference) -> Bool {
  let Transaction { inputs, mint, .. } = self
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let own_nft = get_unique_token_name(own_input.output.value, own_hash)
  quantity_of(mint, own_hash, own_nft) == -1
}

pub fn validate_vote_tally(
  proposal_policy: PolicyId,
  datum: VoteDatum,
  out_idx: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, .. } = self
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

  let refund_ok = {
    let own_input = resolve_input(inputs, own_ref)
    let refund_output = list.expect_at(outputs, out_idx)

    expect  
        Output { address, value, datum: output_datum, reference_script: None }
      = refund_output

    let correct_tag = {
      let expected_datum = InlineDatum(own_ref)
      output_datum == expected_datum
    }
    let correct_value = {
      let input_lovelace = lovelace_of(own_input.value)
      assets.match(value, from_lovelace(input_lovelace), >=)
    }
    let correct_address = address.payment_credential == datum.stake_owner

    and {
      correct_tag,
      correct_value,
      correct_address,
    }
  }

  and {
    tallied,
    refund_ok,
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
