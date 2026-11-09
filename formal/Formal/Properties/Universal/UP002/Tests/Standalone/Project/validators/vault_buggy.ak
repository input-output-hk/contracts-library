//// Buggy copy of the demo vault: `else` accepts every other purpose, so
//// anyone can mint under its hash, and `spend` never checks the owner.

use cardano/transaction.{OutputReference, Transaction}

pub type VaultDatum {
  owner: ByteArray,
}

validator vault_buggy {
  spend(
    _datum: Option<VaultDatum>,
    _redeemer: Data,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    True
  }

  else(_) {
    True
  }
}
