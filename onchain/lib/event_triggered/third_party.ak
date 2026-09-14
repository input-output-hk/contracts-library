//// Third-party logic (withdraw-0) — the keeper-driven graduation gate
//// (§2 P3, §5).
////
//// A keeper detects the settlement event and assembles the graduation
//// transaction; nothing self-executes — the predicate approves the resulting
//// burn iff the event condition holds (§3.1, §5). The condition is *not*
//// hardcoded here: the final validator supplies it as the `rule_check` hook
//// (Q-RULE-1) — the default wiring demands a pluggable `Credential` to
//// authorize (key → signature, script → withdraw-0), and forks plug
//// anything (a custom oracle predicate reading event facts via reference
//// inputs, a quorum, ...). Per-holder policies remain expressible inside a
//// rule *script*: it receives the whole transaction, including the
//// deployer-defined per-holder datums of the subject instruments.
////
//// Holder assurance (Q-GRAD-2, candidate stance 2): a `Graduate` dispatch
//// coexists with the `issuance_mint`-invoked `Burn` mode in the same
//// transaction, which requires the burned owners' consent — an inline
//// verification-key stake credential must sign, an inline script stake
//// credential must run its withdraw-0 (see `issuance.owner_authorized`). So
//// this path is *keeper assembles, owners co-sign*: the keeper detects the
//// event and batches the work, but nothing burns without each owner's
//// authorization, and destinations are consented by signing. On the
//// holder-signed path the core `transfer` validator enforces the same
//// ownership signatures.
////
//// Q-RULE-2 stance, baked: extraction from governed tokens is admitted
//// **only** as part of an event-conditioned, owner-consented graduation
//// burn — a keeper-driven plain move is never approvable in this version,
//// while freeze remains unconditional at the base layer and needs no
//// approval here. Registration and node updates pin
//// `third_party_logic_script` to this script's hash (see
//// `issuance.pinned_stance`), so the stance cannot be swapped out later;
//// the disclosure duty falls to the rule's owner.
////
//// The base-layer guarantee keeps graduation pure issuance, never mixed
//// with a registry reconfiguration (§3.1).

use aiken/collection/dict
use aiken/collection/list
use cardano/assets.{tokens}
use cardano/transaction.{Transaction}
use event_triggered/types.{ThirdPartyParams}

/// Validate one `SpendViaThirdParty` dispatch on governed tokens — the
/// keeper-driven half of graduation/retirement. Runs once per transaction,
/// however many subject UTxOs the spend consumes.
///
/// `rule_check` is the pluggable event rule supplied by the final validator
/// (Q-RULE-1): it decides whether the event condition holds for this
/// transaction, however it sees fit. Owner consent and graduated-value
/// conservation are enforced by the issuance logic's `Burn` mode, which runs
/// in the same transaction.
pub fn validate(
  self: Transaction,
  params: ThirdPartyParams,
  rule_check: fn(Transaction) -> Bool,
) -> Bool {
  // The claimed graduation must actually burn governed tokens: the shape
  // cross-check keeps the mode honest (a keeper claiming graduation while
  // only moving tokens is rejected — extraction is graduation-only in this
  // version).
  let burn_present = tokens(self.mint, params.own_policy)
    |> dict.to_pairs()
    |> list.any(fn(entry) { entry.2nd < 0 })

  and {
    rule_check(self),
    burn_present,
  }
}
