use aiken/collection/list
use cardano/address.{Script}
use cardano/assets
use cardano/transaction.{OutputReference, Transaction}

validator enforcing {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(own_input) =
      list.find(self.inputs, fn(input) { input.output_reference == own_ref })
    expect Script(own_hash) = own_input.output.address.payment_credential
    expect [continuation, ..] = self.outputs
    continuation.address.payment_credential == Script(own_hash) && assets.quantity_of(
      continuation.value,
      "zzzzjunk",
      "zzzzjunk",
    ) == 0
  }

  else(_) {
    fail
  }
}
