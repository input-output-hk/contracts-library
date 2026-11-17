use cardano/transaction.{OutputReference, Transaction}

validator stake_control {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    let own_input = transaction.resolve_input(self.inputs, own_ref)
    expect [continuation, ..] = self.outputs
    and {
      continuation.address.payment_credential == own_input.address.payment_credential,
      continuation.address.stake_credential == own_input.address.stake_credential,
    }
  }

  else(_) {
    fail
  }
}
