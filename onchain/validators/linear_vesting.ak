//// Reference validator for linear vesting.
//// A thin wrapper that dispatches on the redeemer and delegates to the
//// reusable logic in `lib/vesting/linear.ak`. Consumers may use this script
//// as-is or embed the `linear` functions in their own validator.

use cardano/transaction.{OutputReference, Transaction, find_input}
use vesting/linear
use vesting/types.{Cancel, Claim, VestingDatum, VestingRedeemer}

validator linear_vesting {
  spend(
    datum: Option<VestingDatum>,
    redeemer: VestingRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(vesting_datum) = datum
    when redeemer is {
      Claim -> {
        expect Some(own_input) = find_input(self.inputs, own_ref)
        linear.validate_claim(vesting_datum, own_input.output, self)
      }
      Cancel -> linear.validate_cancel(vesting_datum, self)
    }
  }
}
