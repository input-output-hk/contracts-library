use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use upgradeability/counter.{
  CounterDatum, CounterRedeemer, Tick, Upgrade, validate_counter_tick,
}
use upgradeability/migrate.{validate_upgrade}

/// Opt-in V1 of the versioned counter demo.
///
/// Ordinary ticks use the native counter logic. The dedicated `Upgrade` path
/// requires the UTxO owner's authorization (native consent) **and** the
/// migration script registered for this script's own hash, so a governance
/// repoint of the migration script can never move a user's funds without that
/// user's signature.
validator versioned_counter_v1(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) {
  spend(
    datum: Option<CounterDatum>,
    redeemer: CounterRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(counter_datum) = datum
    when redeemer is {
      Tick -> validate_counter_tick(self, own_ref)
      Upgrade ->
        validate_upgrade(
          counter_datum.owner,
          settings_policy,
          settings_token_name,
          own_ref,
          self,
        )
    }
  }

  else(_) {
    fail
  }
}
