//// Reference settings validator module: dispatches the spend/mint handlers to
//// `settings/reference` with the permissive `validate_datum` stub.
//// See `docs/settings/spec.md` §3.d and §6.a.

use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use settings/reference
use settings/types.{MintRedeemer, SettingsDatum, SpendRedeemer}

/// Reference settings validator: any well-formed value is admissible
/// (`True`), per spec §3.d (see `docs/settings/spec.md`). Everything else is
/// shared with `settings_typed`.
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
    reference.reference_spend(
      propose_auth,
      apply_auth,
      apply_delay,
      settings_token_name,
      datum,
      redeemer,
      own_ref,
      self,
      fn(_) { True },
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
      fn(_) { True },
    )
  }

  else(_) {
    fail
  }
}
