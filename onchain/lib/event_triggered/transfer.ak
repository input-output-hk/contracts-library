//// Transfer logic (withdraw-0) — the P1 permissive-transfer base (§2 P1).
////
//// A registered token must ship a `transfer_logic_script`, and the core
//// `transfer` validator requires its withdraw-0 on every owner transfer, so
//// "permissive transfer" is a predicate that approves everything — not the
//// absence of one (09-DEVELOPING-SUBSTANDARDS.md). This profile imposes no
//// transfer rules: ownership is never gated and tokens move as freely as a
//// native token (§1).
////
//// Everything the instrument governs lives elsewhere, per §2's split:
////
//// - P2 event rules and the keeper-driven graduation path are the
////   third-party logic (`third_party.ak`) — keeper-submitted
////   `SpendViaThirdParty` actions gated by the pluggable `rule` credential.
//// - The burn's mint-side authority is the issuance logic (`Burn` mode:
////   rule-gated + 1:1 graduated conservation, Q-GRAD-2). Any negative mint
////   under the governed policy fails there, so this predicate needs no burn
////   guard of its own — the mint is the single chokepoint.
//// - Per-holder datums are static (`InstrumentDatum { rule, params }`):
////   the owner path never needs to rewrite them and the third-party
////   envelope preserves them, so there is no state machine to police here.

use cardano/transaction.{Transaction}

/// Approve every owner transfer (P1). The core `transfer` validator already
/// verified ownership, custody and value preservation; the substandard adds
/// no rule.
pub fn validate(_self: Transaction) -> Bool {
  True
}
