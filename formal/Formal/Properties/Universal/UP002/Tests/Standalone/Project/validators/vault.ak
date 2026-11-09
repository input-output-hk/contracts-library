//// Demo vault for the universal-property demo: the datum names the owner,
//// and only the owner may spend. `else` rejects every other purpose.

use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/transaction.{OutputReference, Transaction}

pub type VaultDatum {
  owner: VerificationKeyHash,
}

validator vault {
  spend(
    datum: Option<VaultDatum>,
    _redeemer: Data,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(VaultDatum { owner }) = datum
    list.has(self.extra_signatories, owner)
  }

  else(_) {
    fail
  }
}
