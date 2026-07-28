use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use settings/mint.{validate_burn, validate_mint}
use settings/spend.{validate_apply, validate_close, validate_propose}
use settings/types.{
  Apply, Burn, Close, Mint, MintRedeemer, Propose, SettingsDatum, SpendRedeemer,
}

validator settings(
  seed_utxo: OutputReference,
  propose_auth: Credential,
  apply_auth: Credential,
  apply_delay: Int,
  settings_token_name: AssetName,
) {
  spend(
    datum: Option<SettingsDatum>,
    redeemer: SpendRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    when redeemer is {
      Propose { out_ix } ->
        validate_propose(
          propose_auth,
          apply_delay,
          datum,
          out_ix,
          own_ref,
          self,
          settings_token_name,
          validate_datum,
        )
      Apply { out_ix } ->
        validate_apply(
          apply_auth,
          datum,
          out_ix,
          own_ref,
          self,
          settings_token_name,
          validate_datum,
        )
      Close -> validate_close(own_ref, self)
    }
  }

  mint(redeemer: MintRedeemer, own_policy: PolicyId, self: Transaction) {
    when redeemer is {
      Mint { out_ix } ->
        validate_mint(
          seed_utxo,
          apply_auth,
          out_ix,
          own_policy,
          self,
          settings_token_name,
          validate_datum,
        )
      Burn -> validate_burn(apply_auth, own_policy, self)
    }
  }

  else(_) {
    fail
  }
}

fn validate_datum(_datum: Data) {
  True
}
