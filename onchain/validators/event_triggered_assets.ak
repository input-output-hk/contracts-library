//// Reference validator for event-triggered assets (CIP-113 substandard,
//// docs/explorations/event-triggered-assets.md). Thin wrapper dispatching on
//// the redeemers and delegating to the stubbed predicates in
//// `lib/event_triggered/*` — all permissive for now, pending triage (§7).

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use event_triggered/graduation.{validate_graduate, validate_retire}
use event_triggered/rules.{validate_event}
use event_triggered/types.{
  ApplyEvent, EventAssetDatum, Graduate, MintRedeemer, Retire, SpendRedeemer,
}

validator event_triggered_assets {
  spend(
    datum: Option<EventAssetDatum>,
    redeemer: SpendRedeemer,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    let ApplyEvent = redeemer
    validate_event(datum, self)
  }

  mint(redeemer: MintRedeemer, own_policy: PolicyId, self: Transaction) {
    when redeemer is {
      Graduate -> validate_graduate(own_policy, self)
      Retire -> validate_retire(own_policy, self)
    }
  }

  else(_) {
    fail
  }
}
