//// The stepped counter: a second schema for forced counters, showing how a
//// logic upgrade evolves the datum of UTxOs that never move.

use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use upgradeability/counter.{settled_by, validate_genesis}

/// Every shape a stepped logic must read. `Unstepped` encodes exactly like
/// `CounterDatum` (constructor 0, same fields), so counters written under the
/// first logic decode as it. Each tick writes `Stepped`.
pub type SteppedCounter {
  Unstepped {
    count: Int,
    owner: Credential,
    prev_input: Option<OutputReference>,
  }
  Stepped {
    count: Int,
    owner: Credential,
    prev_input: Option<OutputReference>,
    step: Int,
  }
}

/// Settle the input at `own_ref` with a `Stepped` continuation that adds its
/// step to `count` (1 for an `Unstepped` counter: convert on touch).
pub fn validate_stepped_tick(
  self: Transaction,
  own_ref: OutputReference,
) -> Bool {
  expect Some(input) = find_input(self.inputs, own_ref)
  expect InlineDatum(raw) = input.output.datum
  expect state: SteppedCounter = raw
  let (count, owner, step) = when state is {
    Unstepped { count, owner, .. } -> (count, owner, 1)
    Stepped { count, owner, step, .. } -> (count, owner, step)
  }
  let continuation: Data = Stepped {
    count: count + step,
    owner,
    prev_input: Some(own_ref),
    step,
  }
  settled_by(self, input.output.address, continuation, input.output)
}

/// Genesis writes the new shape only: a fresh `Stepped` counter with a
/// positive step.
pub fn validate_stepped_genesis(self: Transaction, policy: PolicyId) -> Bool {
  validate_genesis(
    self,
    policy,
    fn(raw) {
      if raw is Stepped { count, prev_input, step, .. }: SteppedCounter {
        and {
          count == 0,
          prev_input == None,
          step > 0,
        }
      } else {
        False
      }
    },
  )
}
