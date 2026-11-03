use aiken/collection/list
use cardano/transaction.{OutputReference, Transaction}
use preparation_types.{Action, KeyDatum}

validator missing_signature {
  spend(
    datum: Option<KeyDatum>,
    redeemer: Action,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(KeyDatum { controller: _controller }) = datum
    expect Action.Withdraw = redeemer
    list.length(self.inputs) == 1
  }

  else(_) {
    fail
  }
}
