use aiken/builtin.{un_constr_data}
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use settings/reference
use settings/types.{MintRedeemer, SettingsDatum, SpendRedeemer}

/// Setting values must be `Constr(0, [_])` — a single-field constructor whose
/// field may be any `Data` (spec §3.1, §7 R7). `un_constr_data` halts on
/// non-constructor `Data`, so an out-of-shape value rejects the transaction.
/// Everything else is shared with the reference `settings` validator.
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

/// Admissible values are exactly `Constr(0, [_])` — a single-field
/// constructor whose field may be any `Data`.
fn validate_datum(data: Data) {
  let constr = un_constr_data(data)
  constr.1st == 0 && when constr.2nd is {
    [_field] -> True
    _ -> False
  }
}
