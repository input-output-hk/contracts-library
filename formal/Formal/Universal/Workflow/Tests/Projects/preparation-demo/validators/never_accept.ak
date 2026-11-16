use cardano/transaction.{OutputReference, Transaction}
use preparation_types.{Action, KeyDatum}

validator never_accept {
  spend(
    datum: Option<KeyDatum>,
    redeemer: Action,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    expect Some(KeyDatum { controller: _controller }) = datum
    expect Action.Withdraw = redeemer
    False
  }

  else(_) {
    fail
  }
}
