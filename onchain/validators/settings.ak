use cardano/assets.{PolicyId}
use cardano/address.{Credential}
use cardano/transaction.{OutputReference, Transaction}
use settings/spend.{validate_propose, validate_apply}
use settings/mint.{validate_mint}
use settings/types.{Propose, Apply, Close, Mint, Burn, SettingsDatum, SpendRedeemer, MintRedeemer}

validator settings(
  seed_utxo: OutputReference,
  propose_auth: Credential,
  apply_auth: Credential,
  apply_delay: Int,
) {
  spend(
    _datum: Option<SettingsDatum>,
    redeemer: SpendRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    when redeemer is {
      Propose { out_ix } -> {
        validate_propose(propose_auth, apply_delay, out_ix, own_ref, self, validate_datum)
      }
      Apply { out_ix } -> {
        validate_apply(apply_auth, apply_delay, out_ix, own_ref, self, validate_datum)
      }
      Close -> {
        // TODO: check NFT burning
        True
      }
    }
  }

  mint(
    redeemer: MintRedeemer,
    own_policy: PolicyId,
    self: Transaction,
  ) {
    when redeemer is {
      Mint { out_ix } -> {
        validate_mint(seed_utxo, apply_auth, out_ix, own_policy, self, validate_datum)
      }
      Burn -> {
        // TODO: check mint quantity < 0
        True
      }
    }
  }

  else(_) {
    fail
  }
}


fn validate_datum(datum: Data) {
  True
}
