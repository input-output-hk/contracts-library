use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/stake/mint.{validate_close_position, validate_create_position}
use dao/stake/spend.{
  validate_stake_close_position, validate_stake_cosign,
  validate_stake_create_proposal, validate_stake_delegate,
  validate_stake_deposit, validate_stake_vote, validate_stake_withdraw,
}
use dao/types.{
  ClosePosition, CloseStakePosition, CosignProposal, CreatePosition,
  CreateProposal, DelegateTo, Deposit, StakePositionDatum,
  StakePositionTokenRedeemer, StakeRedeemer, VoteProposal, Withdraw,
}
use dao/utils.{get_dao_settings}

/// Stake position script: its hash is the stake NFT policy id and the address
/// where positions live. Governance parameters and sibling script hashes are
/// read at runtime from the settings UTxO located by its NFT.
validator stake(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) {
  mint(
    redeemer: StakePositionTokenRedeemer,
    own_policy: PolicyId,
    self: Transaction,
  ) {
    when redeemer is {
      CreatePosition { owner_utxo, out_idx } ->
        validate_create_position(
          staked_token_policy,
          staked_token_name,
          owner_utxo,
          own_policy,
          out_idx,
          self,
        )
      CloseStakePosition -> validate_close_position(own_policy, self)
    }
  }

  spend(
    datum: Option<StakePositionDatum>,
    redeemer: StakeRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(stake_datum) = datum
    let settings = get_dao_settings(self, settings_policy, settings_token_name)
    when redeemer is {
      Deposit ->
        validate_stake_deposit(
          staked_token_policy,
          staked_token_name,
          stake_datum,
          own_ref,
          self,
        )
      DelegateTo { delegatee } ->
        validate_stake_delegate(
          staked_token_policy,
          staked_token_name,
          stake_datum,
          delegatee,
          own_ref,
          self,
        )
      Withdraw { amount } ->
        validate_stake_withdraw(
          staked_token_policy,
          staked_token_name,
          stake_datum,
          amount,
          own_ref,
          self,
        )
      ClosePosition ->
        validate_stake_close_position(
          staked_token_policy,
          staked_token_name,
          stake_datum,
          own_ref,
          self,
        )
      CreateProposal ->
        validate_stake_create_proposal(
          settings,
          staked_token_policy,
          staked_token_name,
          stake_datum,
          own_ref,
          self,
        )
      CosignProposal { proposal_id } ->
        validate_stake_cosign(
          settings,
          staked_token_policy,
          staked_token_name,
          stake_datum,
          proposal_id,
          own_ref,
          self,
        )
      VoteProposal { proposal_id, voted_option: _ } ->
        validate_stake_vote(
          settings,
          staked_token_policy,
          staked_token_name,
          stake_datum,
          proposal_id,
          own_ref,
          self,
        )
    }
  }

  else(_) {
    fail
  }
}
