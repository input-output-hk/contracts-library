use cardano/transaction.{OutputReference, Transaction}
use upgradeability/counter.{
  CounterRedeemer, Tick, Upgrade, validate_counter_tick,
}

/// V2 of the counter demo: a plain, native counter with no upgrade
/// path. Users reach it by opting in to a V1 → V2 migration; their state then
/// lives under this new, immutable script.
validator counter_v2 {
  spend(
    _datum: Option<Data>,
    redeemer: CounterRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    when redeemer is {
      Tick -> validate_counter_tick(self, own_ref)
      Upgrade -> fail
    }
  }

  else(_) {
    fail
  }
}
