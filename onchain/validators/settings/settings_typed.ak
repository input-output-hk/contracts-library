use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use settings/reference
use settings/typed.{validate_datum}
use settings/types.{MintRedeemer, SettingsDatum, SpendRedeemer}

/// Setting values must be `Constr(0, [_])` — a single-field constructor whose
/// field may be any `Data` (spec §3.d, §6.d R7); the predicate lives in
/// `settings/typed`. Everything else is shared with the reference `settings`
/// validator.
validator settings_typed(
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
    reference.reference_spend(
      propose_auth,
      apply_auth,
      apply_delay,
      settings_token_name,
      datum,
      redeemer,
      own_ref,
      self,
      validate_datum,
    )
  }

  mint(redeemer: MintRedeemer, own_policy: PolicyId, self: Transaction) {
    reference.reference_mint(
      seed_utxo,
      apply_auth,
      settings_token_name,
      redeemer,
      own_policy,
      self,
      validate_datum,
    )
  }

  else(_) {
    fail
  }
}
