//// Transfer logic (withdraw-0) — the P1 permissive-transfer base (§4.2).
////
//// A registered token must ship a `transfer_logic_script`, and the core
//// `transfer` validator requires its withdraw-0 on every owner transfer, so
//// "permissive transfer" is a predicate that approves everything — not the
//// absence of one (09-DEVELOPING-SUBSTANDARDS.md). This instrument imposes
//// no transfer rules: ownership is never gated, the token moves as freely as
//// a native token at every point of its life, before and after the
//// deadlines (§4.2, I2, Q-RULE-3) — DEX/venue-compatible.
////
//// The one exception is the graduation's spend-side event gate (§4.5,
//// Q-RULE-1): a transaction that burns governed tokens is a graduation and
//// must reach the baked `d4` — the deadline check lives inside the
//// substandard logic that already runs, and approves iff the validity range
//// reaches `d4` (the transaction's own validity range; no oracle, §5).
//// Plain transfers read no time bound (§4.2, §4.3).
////

use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{is_entirely_after}
use cardano/address.{Credential}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{Transaction}
use event_triggered/registry
use event_triggered/types.{TransferParams}

/// Approve every owner transfer (P1, §4.2). The core `transfer` validator
/// already verified ownership, custody and value preservation; the
/// substandard adds no rule — except the graduation deadline gate below. The
/// governed policy id resolves at runtime from the referenced registry node
/// (09-DEVELOPING-MODULES, "Finding your own policy id": the policy id
/// depends on the issuance credential, so this validator cannot bake it).
pub fn validate(
  account: Credential,
  self: Transaction,
  params: TransferParams,
) -> Bool {
  let referenced = registry.outputs_of(self.reference_inputs)
  expect [(policy, _)] = registry.governing_transfer(
    referenced,
    params.registry_node_cs,
    account,
  )
  if is_graduation(self, policy) {
    // Event gate (Q-RULE-1, §4.5): the validity range must reach `d4`.
    // `is_entirely_after(range, d4 - 1)` ⟺ the lower bound is ≥ d4.
    is_entirely_after(self.validity_range, params.final_deadline - 1)
  } else {
    // A plain transfer reads no time bound (§4.2, §5).
    True
  }
}

/// Is this transaction burning governed tokens? A negative mint under the
/// policy is a graduation attempt — whatever the spend path.
fn is_graduation(self: Transaction, policy: PolicyId) -> Bool {
  tokens(self.mint, policy)
    |> dict.values
    |> list.any(fn(quantity) { quantity < 0 })
}
