//// Linear-vesting validator.
////
//// A faithful Aiken port of Anastasia Labs' `linear-vesting`. Not parameterised:
//// every vesting arrangement lives entirely in the datum of its locked UTxO, so
//// one deployed script serves arbitrarily many independent vestings.

use cardano/transaction.{OutputReference, Transaction}
use vesting/types.{FullUnlock, PartialUnlock, VestingDatum, VestingRedeemer}
use vesting/validation

validator vesting {
  spend(
    datum: Option<VestingDatum>,
    redeemer: VestingRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(vesting_datum) = datum
    when redeemer is {
      PartialUnlock -> validation.partial_unlock(vesting_datum, own_ref, self)
      FullUnlock -> validation.full_unlock(vesting_datum, self)
    }
  }
}
