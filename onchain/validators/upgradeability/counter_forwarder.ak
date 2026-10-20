use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use upgradeability/forward.{validate_forward}

/// Forced forwarder for the counter demo.
///
/// It holds the counter state but carries no business logic: every spend is
/// admitted only if the logic script currently registered for this script's own
/// hash runs as a reward withdrawal in the same transaction. Repointing the
/// registry entry upgrades the protocol **without moving any funds**, and the
/// change applies to every user at once (hence *forced*).
validator counter_forwarder(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    validate_forward(settings_policy, settings_token_name, own_ref, self)
  }

  else(_) {
    fail
  }
}
