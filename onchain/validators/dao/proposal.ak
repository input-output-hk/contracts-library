use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/proposal/mint.{validate_create_proposal, validate_finish_proposal}
use dao/proposal/spend.{
  validate_accept_draft, validate_cosign, validate_end_proposal,
  validate_end_voting_stage, validate_reject_draft, validate_tally_votes,
}
use dao/types.{
  AcceptDraft, BurnProposal, Cosign, EndProposal, EndVotingStage, MintProposal,
  ProposalDatum, ProposalRedeemer, ProposalTokenRedeemer, RejectDraft,
  TallyVotes,
}
use dao/utils.{get_dao_settings}

validator proposal(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) {
  mint(redeemer: ProposalTokenRedeemer, own_policy: PolicyId, self: Transaction) {
    when redeemer is {
      MintProposal { results, out_idx } -> {
        let settings = get_dao_settings(
          self,
          settings_policy,
          settings_token_name,
        )
        validate_create_proposal(
          settings,
          staked_token_policy,
          staked_token_name,
          own_policy,
          out_idx,
          results,
          self,
        )
      }
      BurnProposal -> validate_finish_proposal(own_policy, self)
    }
  }

  spend(
    datum: Option<ProposalDatum>,
    redeemer: ProposalRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(proposal_datum) = datum
    let settings = get_dao_settings(self, settings_policy, settings_token_name)
    when redeemer is {
      Cosign ->
        validate_cosign(
          settings.stake_validator,
          staked_token_policy,
          staked_token_name,
          proposal_datum,
          own_ref,
          self,
        )
      AcceptDraft -> validate_accept_draft(proposal_datum, own_ref, self)
      RejectDraft -> validate_reject_draft(proposal_datum, own_ref, self)
      EndVotingStage -> validate_end_voting_stage(proposal_datum, own_ref, self)
      TallyVotes ->
        validate_tally_votes(
          settings.vote_validator,
          proposal_datum,
          own_ref,
          self,
        )
      EndProposal -> validate_end_proposal(proposal_datum, own_ref, self)
    }
  }

  else(_) {
    fail
  }
}
