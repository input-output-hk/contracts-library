use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/proposal/mint.{validate_create_proposal, validate_finish_proposal}
use dao/proposal/spend.{validate_proposal_spend}
use dao/types.{
  BurnProposal, MintProposal, ProposalDatum, ProposalRedeemer,
  ProposalTokenRedeemer,
}
use dao/utils.{get_dao_settings}

validator proposal(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  settings_utxo: OutputReference,
  settings_token_name: AssetName,
) {
  mint(redeemer: ProposalTokenRedeemer, own_policy: PolicyId, self: Transaction) {
    let settings = get_dao_settings(self, settings_utxo, settings_token_name)
    when redeemer is {
      MintProposal { out_idx } ->
        validate_create_proposal(
          settings,
          staked_token_policy,
          staked_token_name,
          own_policy,
          out_idx,
          self,
        )
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
    let settings = get_dao_settings(self, settings_utxo, settings_token_name)
    validate_proposal_spend(
      settings.vote_validator,
      settings.stake_validator,
      staked_token_policy,
      staked_token_name,
      proposal_datum,
      redeemer,
      own_ref,
      self,
    )
  }

  else(_) {
    fail
  }
}
