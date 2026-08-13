use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/mint.{validate_create_proposal}
use dao/types.{CreateProposal, ProposalTokenRedeemer}

validator dao(
  settings_utxo: OutputReference,
  stake_nft_policy: PolicyId,
  stake_nft_name: AssetName,
  stake_token_policy: PolicyId,
  stake_token_name: AssetName,
) {
  mint(redeemer: ProposalTokenRedeemer, own_policy: PolicyId, self: Transaction) {
    let CreateProposal = redeemer
    validate_create_proposal(
      settings_utxo,
      stake_nft_policy,
      stake_nft_name,
      stake_token_policy,
      stake_token_name,
      own_policy,
      self,
    )
  }

  else(_) {
    fail
  }
}
