//// Reference substandard wiring for the event-triggered assets CIP-113
//// substandard (issue #28). Three withdraw-zero validators per
//// 09-DEVELOPING-SUBSTANDARDS.md — issuance logic, transfer logic, and
//// third-party logic — registered in the token's `RegistryNode` and invoked
//// by the core infrastructure: `issuance_mint` / `registry_mint` /
//// `registry_spend` for the issuance logic, and the core `transfer` /
//// `third_party` stake validators for the other two. The shared
//// programmable-logic base custodies all token UTxOs; there is deliberately
//// no spend or mint endpoint here.
////
//// Split per the exploration (§2, docs/event-triggered-assets/exploration.md):
//// - `transfer_logic` — pure P1, permissive (imposes no transfer rules);
//// - `third_party_logic` — the keeper-driven graduation gate: event-
////   conditioned burns only, gated by the deployment's pluggable event rule
////   (Q-RULE-2: extraction admitted only as part of graduation);
//// - `issuance_logic` — the burn's mint-side authority (mode-aware,
////   Q-GRAD-2) plus the registry lifecycle gates.
////
//// **This file is the customization point** (ARCHITECTURE.md §2.1: use the
//// reference validator as-is, or embed the lib predicates in your own): the
//// P2 event rule is a validator-level parameter, wired below into the
//// `rule_check` hook the lib predicates accept. The default demands the
//// params' `rule` `Credential` to authorize — a verification key by
//// signature, a script by its withdraw-0 (an oracle/attestation script can
//// thus stand in as the event source). Fork the validator to plug any other
//// rule semantics: a custom oracle predicate, per-holder decoding of the
//// deployer-defined datum, a multisig quorum, ... The base library imposes
//// only *that a check exists and returns one Bool per transaction*.
////
//// Parameterize, compile, and register each validator's credential in the
//// node's matching field; the off-chain builders then include the matching
//// withdraw-0 in every transaction.

use authorization.{is_authorized}
use cardano/address.{Credential}
use cardano/transaction.{Transaction}
use event_triggered/issuance
use event_triggered/third_party
use event_triggered/transfer
use event_triggered/types.{
  IssuanceAction, IssuanceParams, ThirdPartyAction, ThirdPartyParams,
  TransferAction,
}

/// The default P2 event rule (Q-RULE-1): the deployment's `rule` credential
/// must authorize the transaction — a verification key by signature, a
/// script by its withdraw-0. Both `third_party_logic` and the issuance
/// logic's `Burn` mode are wired with it, so graduation fires under the same
/// event condition the rules enforce (Q-GRAD-2).
fn rule_check(rule: Credential) -> fn(Transaction) -> Bool {
  fn(tx: Transaction) {
    is_authorized(rule, tx.extra_signatories, tx.withdrawals)
  }
}

/// Issuance logic (withdraw-0): mode-aware mint/burn authority and registry
/// lifecycle — Register / UpdateNode / Mint / Burn (see `issuance.validate`).
validator issuance_logic(p: IssuanceParams) {
  withdraw(redeemer: IssuanceAction, account: Credential, self: Transaction) {
    issuance.validate(redeemer, account, self, p, rule_check(p.rule))
  }

  else(_) {
    fail
  }
}

/// Transfer logic (withdraw-0): purely permissive — P1 imposes no transfer
/// rules (§2 P1).
validator transfer_logic {
  withdraw(_redeemer: TransferAction, _account: Credential, self: Transaction) {
    transfer.validate(self)
  }

  else(_) {
    fail
  }
}

/// Third-party logic (withdraw-0): the keeper-driven graduation gate —
/// event-conditioned burns only, gated by the deployment's event rule, with
/// graduated payouts pinned back to the burned holders (§2 P3, §5, Q-RULE-2,
/// Q-GRAD-2). Note `p.graduated_policy` must mirror the issuance params' one.
validator third_party_logic(p: ThirdPartyParams) {
  withdraw(_redeemer: ThirdPartyAction, _account: Credential, self: Transaction) {
    third_party.validate(self, p, rule_check(p.rule))
  }

  else(_) {
    fail
  }
}
