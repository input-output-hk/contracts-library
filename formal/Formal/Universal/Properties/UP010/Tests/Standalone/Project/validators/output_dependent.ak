use aiken/collection/list
use cardano/address.{Script}
use cardano/transaction.{OutputReference, Transaction}

validator output_dependent {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    list.any(
      self.outputs,
      fn(output) {
        when output.address.payment_credential is {
          Script(_) -> True
          _ -> False
        }
      },
    )
  }

  else(_) {
    fail
  }
}
