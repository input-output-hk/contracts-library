use aiken/collection/list
use cardano/transaction.{OutputReference, Transaction}
use preparation_types.{Action, KeyDatum}

validator controller_gate {
  spend(
    datum: Option<KeyDatum>,
    redeemer: Action,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(KeyDatum { controller }) = datum
    expect Action.Withdraw = redeemer
    list.has(self.extra_signatories, controller) && list.length(self.inputs) == 1
  }

  else(_) {
    fail
  }
}
