use aiken/collection/list
use cardano/address.{Script}
use cardano/transaction.{OutputReference, Transaction}

validator continuation_gate {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(own_input) =
      list.find(self.inputs, fn(input) { input.output_reference == own_ref })
    expect Script(_) = own_input.output.address.payment_credential
    expect [first_output, ..] = self.outputs
    first_output.address.payment_credential == own_input.output.address.payment_credential
  }

  else(_) {
    fail
  }
}
