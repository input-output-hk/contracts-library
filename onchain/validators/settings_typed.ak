use aiken/builtin.{un_constr_data}
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use settings/mint.{validate_burn, validate_mint}
use settings/spend.{validate_apply, validate_close, validate_propose}
use settings/types.{
  Apply, Burn, Close, Mint, MintRedeemer, Propose, SettingsDatum, SpendRedeemer,
}

/// Fork of the `settings` validator (see `validators/settings.ak`) that ships a
/// concrete `validate_datum` predicate instead of the constant `True` (spec
/// §3.1, §7 R7). The setting value must be `Constr(0, [_])` — a single-field
/// constructor, field of any type. Everything else is shared with the reference
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
          validate_datum_typed,
        )
      Apply { out_ix } ->
        validate_apply(
          apply_auth,
          datum,
          out_ix,
          own_ref,
          self,
          settings_token_name,
          validate_datum_typed,
        )
      Close -> validate_close(apply_auth, own_ref, self)
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
          validate_datum_typed,
        )
      Burn -> validate_burn(own_policy, self)
    }
  }

  else(_) {
    fail
  }
}

/// Admissible values are exactly `Constr(0, [_])` — a single-field constructor
/// whose field may be any `Data`.
///
/// `un_constr_data` halts on non-constructor `Data`, so an out-of-shape value
/// rejects the transaction.
fn validate_datum_typed(data: Data) {
  let constr = un_constr_data(data)
  constr.1st == 0 && when constr.2nd is {
    [_field] -> True
    _ -> False
  }
}
