use aiken/collection/list
use cardano/transaction.{OutputReference, Transaction}

validator membership {
  spend(
    datum: Option<ByteArray>,
    redeemer: List<ByteArray>,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    expect Some(key) = datum
    list.has(redeemer, key)
  }

  else(_) {
    fail
  }
}
