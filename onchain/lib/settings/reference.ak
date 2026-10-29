//// The shared `settings` validator body: dispatches spend and mint redeemers
//// to the matching rules of `settings/spend` and `settings/mint`, passing
//// through the `validate_datum` predicate each concrete validator chooses.

use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use settings/mint.{validate_burn, validate_mint}
use settings/spend.{validate_apply, validate_close, validate_propose}
use settings/types.{
  Apply, Burn, Close, Mint, MintRedeemer, Propose, SettingsDatum, SpendRedeemer,
}

/// Dispatch a `Spend` redeemer to the matching spend rule.
pub fn reference_spend(
  propose_auth: Credential,
  apply_auth: Credential,
  apply_delay: Int,
  settings_token_name: AssetName,
  datum: Option<SettingsDatum>,
  redeemer: SpendRedeemer,
  own_ref: OutputReference,
  self: Transaction,
  validate_datum: fn(Data) -> Bool,
) -> Bool {
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
    Close -> validate_close(apply_auth, own_ref, self)
  }
}

/// Dispatch a `Mint` redeemer to the matching mint rule.
pub fn reference_mint(
  seed_utxo: OutputReference,
  apply_auth: Credential,
  settings_token_name: AssetName,
  redeemer: MintRedeemer,
  own_policy: PolicyId,
  self: Transaction,
  validate_datum: fn(Data) -> Bool,
) -> Bool {
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
    Burn -> validate_burn(own_policy, self)
  }
}
