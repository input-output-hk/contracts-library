use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/types.{BurnVotes, MintVote, VoteDatum, VoteRedeemer, VoteTokenRedeemer}
use dao/vote/mint.{validate_burn_votes, validate_mint_vote}
use dao/vote/spend.{validate_vote_spend}

/// Vote artifact script: its hash is the vote NFT policy id and the address
/// where vote artifacts live while awaiting tally.
validator vote(
  stake_nft_policy: PolicyId,
  stake_token_policy: PolicyId,
  stake_token_name: AssetName,
  proposal_policy: PolicyId,
) {
  mint(redeemer: VoteTokenRedeemer, own_policy: PolicyId, self: Transaction) {
    when redeemer is {
      MintVote ->
        validate_mint_vote(
          stake_nft_policy,
          stake_token_policy,
          stake_token_name,
          proposal_policy,
          own_policy,
          self,
        )
      BurnVotes -> validate_burn_votes(own_policy, self)
    }
  }

  spend(
    datum: Option<VoteDatum>,
    redeemer: VoteRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(vote_datum) = datum
    validate_vote_spend(proposal_policy, vote_datum, redeemer, own_ref, self)
  }

  else(_) {
    fail
  }
}
