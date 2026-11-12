use aiken/crypto.{VerificationKeyHash}

pub type KeyDatum {
  controller: VerificationKeyHash,
}

pub type Action {
  Withdraw
}
