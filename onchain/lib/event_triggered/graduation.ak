//// P3 — graduation / unwrap (§2, §3.1). Programmable custody forbids
//// moving CIP-113 tokens to a non-programmable address (§5), so graduation
//// is necessarily burn-the-programmable + mint-the-native. STUB: permissive
//// until triage (§7 Q-GRAD-1, Q-GRAD-2).

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}

/// Event-gated burn + remint into the graduated native token (Q-GRAD-1).
pub fn validate_graduate(_own_policy: PolicyId, _self: Transaction) -> Bool {
  // TODO(#28): gate on the settlement event, burn own-policy tokens, and
  // check the graduated-native mint (asset identity across the swap).
  True
}

/// Burn-only retirement (§3.1: "or simply burns, for retire-style cases").
pub fn validate_retire(_own_policy: PolicyId, _self: Transaction) -> Bool {
  // TODO(#28): burn-only check.
  True
}
