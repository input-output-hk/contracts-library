//// Third-party logic (withdraw-0) — the keeper-driven graduation gate
//// (§2 P3, §5).
////
//// A keeper detects the settlement event and submits a `SpendViaThirdParty`
//// dispatch; nothing self-executes — the predicate approves the resulting
//// burn iff the event condition holds (§3.1, §5). The condition is *not*
//// hardcoded here: the final validator supplies it as the `rule_check` hook
//// (Q-RULE-1) — the default wiring demands a pluggable `Credential` to
//// authorize (key → signature, script → withdraw-0), and forks plug
//// anything (a custom oracle predicate reading event facts via reference
//// inputs, a quorum, ...). Per-holder policies remain expressible inside a
//// rule *script*: it receives the whole transaction, including the
//// deployer-defined per-holder datums of the subject instruments.
////
//// Holder assurance (Q-GRAD-2, candidate stance 2, path-scoped): there is
//// no holder signature on this path — that is what `SpendViaThirdParty`
//// means — so the graduated value is **pinned to the burned holders**: when
//// `graduated_policy` is set, every output carrying graduated tokens must be
//// addressed to an inline stake credential burned in the same transaction.
//// Holder-signed graduation needs no pin (the core `transfer` validator
//// enforces ownership, and destinations are consented by signing), which
//// keeps atomic post-graduation flows free there. Pointer-backed and absent
//// stake credentials fail closed: a graduated payout with no matchable
//// holder identity is rejected. Caveats: mixed-path transactions (holder-
//// signed transfer spends coexisting with keeper third-party spends) get
//// the pin transaction-wide; multi-holder burns match at set level, not
//// exact 1:1 attribution.
////
//// Q-RULE-2 stance, baked: extraction from governed tokens is admitted
//// **only** as part of an event-conditioned graduation burn — a keeper-driven
//// plain move is never approvable in this version, while freeze remains
//// unconditional at the base layer and needs no approval here. Registration
//// and node updates pin `third_party_logic_script` to this script's hash
//// (see `issuance.pinned_stance`), so the stance cannot be swapped out
//// later; the disclosure duty falls to the rule's owner.
////
//// Relies on the issuance logic for the burn's mint-side authority: a
//// `Graduate` dispatch coexists with the `issuance_mint`-invoked `Burn`
//// mode in the same transaction, which independently applies the same event
//// gate and enforces the 1:1 graduated conservation (Q-GRAD-1, Q-GRAD-2).
//// The base-layer guarantee keeps this pure issuance, never mixed with a
//// registry reconfiguration (§3.1).

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Credential, Inline}
use cardano/assets.{PolicyId, Value, tokens}
use cardano/transaction.{Transaction}
use event_triggered/types.{ThirdPartyParams}

/// Validate one `SpendViaThirdParty` dispatch on governed tokens — the
/// keeper-driven half of graduation/retirement. Runs once per transaction,
/// however many subject UTxOs the spend consumes.
///
/// `rule_check` is the pluggable event rule supplied by the final validator
/// (Q-RULE-1): it decides whether the event condition holds for this
/// transaction, however it sees fit.
pub fn validate(
  self: Transaction,
  params: ThirdPartyParams,
  rule_check: fn(Transaction) -> Bool,
) -> Bool {
  let own_policy = params.own_policy

  // The claimed graduation must actually burn governed tokens: the shape
  // cross-check keeps the mode honest (a keeper claiming graduation while
  // only moving tokens is rejected — extraction is graduation-only in this
  // version).
  let burn_present = tokens(self.mint, own_policy)
    |> dict.to_pairs()
    |> list.any(fn(entry) { entry.2nd < 0 })

  // Holder assurance (Q-GRAD-2): the graduated value must land back at a
  // stake credential burned in this transaction. Fail-closed on pointer or
  // absent stake credentials.
  let payouts_pinned = when params.graduated_policy is {
    None -> True
    Some(graduated) -> {
      let holders = self.inputs
        |> list.filter(fn(input) { holds(input.output.value, own_policy) })
        |> list.filter_map(fn(input) { inline_stake(input.output.address) })
      self.outputs
        |> list.filter(fn(output) { holds(output.value, graduated) })
        |> list.all(
            fn(output) {
              when inline_stake(output.address) is {
                Some(holder) -> list.has(holders, holder)
                None -> False
              }
            },
          )
    }
  }

  and {
    rule_check(self),
    burn_present,
    payouts_pinned,
  }
}

// ----------------------------------------------------------------- helpers

/// Does this value carry any token under `policy`? Instrument tokens exist
/// only at the programmable-logic base (the core enforces custody).
fn holds(value: Value, policy: PolicyId) -> Bool {
  !dict.is_empty(tokens(value, policy))
}

/// The inline stake credential of an address, if it has one. Pointer-backed
/// and absent stake credentials are `None`: graduated payouts must be
/// matchable to a burned holder's identity.
fn inline_stake(address: Address) -> Option<Credential> {
  when address.stake_credential is {
    Some(Inline(cred)) -> Some(cred)
    _ -> None
  }
}
