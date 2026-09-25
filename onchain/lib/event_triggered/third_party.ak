//// Third-party logic (withdraw-0) — the permissionless graduation gate
//// (spec §4.5).
////
//// Anyone may submit a `ThirdPartyAct` dispatch on governed tokens — but in
//// this instrument extraction is admitted **only** as part of a graduation
//// (Q-RULE-2): the claimed action must actually burn governed tokens, and
//// the deadline gate must hold. Nothing self-executes; the predicate
//// approves the resulting transaction (§5).
////
//// Holder assurance (Q-GRAD-2): this path needs no signatures, so it only
//// works for tokens whose owner opted in beforehand — the payout payment
//// credential must be the one the owner pre-committed to the token datum on
//// an owner-signed self-transfer (§4.3, preserved byte-for-byte through the
//// paired ghost continuation the core third-party validator enforces). The
//// full conversion validation — burn shape, whole holdings per name,
//// destination binding and the scaled native mirror — runs in the same
//// transaction as the minting logic's `Burn` mode; this predicate adds the
//// spend-side gates. A completer can complete a graduation, never redirect
//// it; absent the commitment the transaction is rejected.
////
//// The base-layer guarantee keeps graduation pure issuance, never mixed
//// with a registry reconfiguration (I7; re-checked by the burn mode).

use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{is_entirely_after}
use cardano/assets.{tokens}
use cardano/transaction.{Transaction}
use event_triggered/types.{ThirdPartyParams}

/// Validate the graduation dispatch — runs once per transaction, however
/// many subject UTxOs the spend consumes.
pub fn validate(self: Transaction, params: ThirdPartyParams) -> Bool {
  // The claimed graduation must actually burn governed tokens (the shape
  // cross-check keeps the mode honest: extraction is graduation-only).
  let burn_present = tokens(self.mint, params.own_policy)
    |> dict.values
    |> list.any(fn(quantity) { quantity < 0 })
  and {
    burn_present,
    // Event gate (Q-RULE-1): the validity range must reach `d4`.
    is_entirely_after(self.validity_range, params.final_deadline - 1),
  }
}
