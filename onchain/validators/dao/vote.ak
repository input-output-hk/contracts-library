use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/types.{
  BurnVotes, Cancel, MintVote, TallyVote, VoteDatum, VoteRedeemer,
  VoteTokenRedeemer,
}
use dao/utils.{get_dao_settings}
use dao/vote/mint.{validate_burn_votes, validate_mint_vote}
use dao/vote/spend.{validate_vote_cancel, validate_vote_tally}

/// Vote artifact script: its hash is the vote NFT policy id and the address
/// where vote artifacts live while awaiting tally.
validator vote(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  settings_utxo: OutputReference,
  settings_token_name: AssetName,
) {
  mint(redeemer: VoteTokenRedeemer, own_policy: PolicyId, self: Transaction) {
    when redeemer is {
      MintVote { out_idx } -> {
        let settings = get_dao_settings(
          self,
          settings_utxo,
          settings_token_name,
        )
        validate_mint_vote(
          settings.proposal_validator,
          settings.stake_validator,
          staked_token_policy,
          staked_token_name,
          own_policy,
          out_idx,
          self,
        )
      }
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
    let settings = get_dao_settings(self, settings_utxo, settings_token_name)
    when redeemer is {
      TallyVote ->
        validate_vote_tally(
          settings.proposal_validator,
          vote_datum,
          own_ref,
          self,
        )
      Cancel -> validate_vote_cancel(vote_datum, own_ref, self)
    }
  }

  else(_) {
    fail
  }
}
