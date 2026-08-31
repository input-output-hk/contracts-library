//// P2 — event-rule hooks (§2). Pluggable rules that modify instrument
//// state or condition transfers/lockups/burns on discrete events, reading
//// event state via reference inputs (pull-based, §5). STUB: permissive
//// until triage (§7 Q-RULE-1).

use cardano/transaction.{Transaction}
use event_triggered/types.{EventAssetDatum}

/// Approve an event-conditioned action on the instrument UTxO.
pub fn validate_event(
  _datum: Option<EventAssetDatum>,
  _self: Transaction,
) -> Bool {
  // TODO(#28): read event state via a reference input, authorize against
  // `datum.rule`, and enforce the state transition.
  True
}
