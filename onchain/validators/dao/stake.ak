use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use dao/stake/mint.{validate_close_position, validate_create_position}
use dao/stake/spend.{validate_stake_spend}
use dao/types.{
  CloseStakePosition, CreatePosition, StakePositionDatum,
  StakePositionTokenRedeemer, StakeRedeemer,
}

/// Stake position script: its hash is the stake NFT policy id and the address
/// where positions live. Governance parameters and sibling script hashes are
/// read at runtime from the settings UTxO at `settings_utxo`.
validator stake(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  settings_utxo: OutputReference,
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
    validate_stake_spend(
      staked_token_policy,
      staked_token_name,
      settings_utxo,
      settings_token_name,
      stake_datum,
      redeemer,
      own_ref,
      self,
    )
  }

  else(_) {
    fail
  }
}
