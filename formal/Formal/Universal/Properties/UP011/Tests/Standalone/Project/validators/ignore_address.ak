use cardano/transaction.{InlineDatum, OutputReference, Transaction}

// Deliberate bug: the first output must carry an inline datum, but its address
// is unchecked. Redirection removes that datum; a payment-credential change does not.
validator ignore_address {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    expect [first, ..] = self.outputs
    expect InlineDatum(_) = first.datum
    True
  }

  else(_) {
    fail
  }
}
