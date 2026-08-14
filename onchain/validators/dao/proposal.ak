use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/proposal/mint.{validate_create_proposal, validate_finish_proposal}
use dao/proposal/spend.{validate_proposal_spend}
use dao/types.{
  BurnProposal, MintProposal, ProposalDatum, ProposalRedeemer,
  ProposalTokenRedeemer,
}

validator proposal(
  settings_utxo: OutputReference,
  stake_nft_policy: PolicyId,
  stake_nft_name: AssetName,
  stake_token_policy: PolicyId,
  stake_token_name: AssetName,
) {
  mint(redeemer: ProposalTokenRedeemer, own_policy: PolicyId, self: Transaction) {
    when redeemer is {
      MintProposal ->
        validate_create_proposal(
          settings_utxo,
          stake_nft_policy,
          stake_nft_name,
          stake_token_policy,
          stake_token_name,
          own_policy,
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
    validate_proposal_spend(
      settings_utxo,
      stake_nft_policy,
      stake_token_policy,
      stake_token_name,
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
