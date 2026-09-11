//// On-chain types for the event-triggered assets CIP-113 substandard
//// (issue #28). See `docs/event-triggered-assets/exploration.md` for the
//// design log and `docs/event-triggered-assets/design.typ` for flows.
////
//// A substandard ships three withdraw-zero validators (issuance, transfer,
//// third-party logic) that the CIP-113 core infrastructure invokes: the
//// shared Programmable Logic Base custodies all token UTxOs and dispatches
//// to the transfer / third-party logic on spends, and the parameterized
//// `issuance_mint` policy invokes the issuance logic on mint/burn
//// (09-DEVELOPING-SUBSTANDARDS.md, "What You Must Implement"). There is
//// deliberately no spend or mint endpoint of our own — the toy sketch's
//// self-custodied script address does not model the CIP-113 base.
////
//// Split per the exploration (§2): P1 is the permissive transfer logic;
//// P2 (event rules) and the keeper-driven graduation path live in the
//// third-party logic; the burn itself is authorized by the issuance logic
//// (§2 P3, Q-GRAD-2). The event rule is *not* hardcoded here: it is a
//// validator-level parameter (Q-RULE-1), wired by the final validator and
//// pluggable by forking it — the base library never interprets the rule,
//// nor the per-holder datum.
////
//// The per-holder datum at the programmable-logic base is **deployer-defined
//// `Data`**: this library defines no datum type and never reads it. Vesting
//// schedules, claim amounts, or any other per-holder payload live there,
//// interpreted by the deployer's rule logic and off-chain builders — both
//// agree on a shape consumer-side (ARCHITECTURE.md: the spec lives outside
//// the on-chain layer).

use aiken/crypto.{ScriptHash}
use cardano/address.{Credential}
use cardano/assets.{PolicyId}

/// Mode redeemer on the issuance-logic withdraw-0. The issuance credential is
/// also the registry-lifecycle authority, so it runs in four contexts and must
/// be told why (09-DEVELOPING-SUBSTANDARDS.md, "Your issuance logic must know
/// why it is running"). Each mode is cross-checked against the transaction
/// shape in `issuance.validate`.
pub type IssuanceAction {
  /// A `RegistryNode` for this substandard instance is being created.
  Register
  /// This token's `RegistryNode` is being updated in place (Q-RULE-3 gate).
  UpdateNode
  /// Mint of the programmable token.
  Mint
  /// Burn of the programmable token: graduation or retirement (P3, Q-GRAD-2).
  Burn
}

/// Redeemer of the transfer-logic withdraw-0. P1 imposes no transfer rules —
/// the predicate approves every owner transfer; the redeemer is typed for
/// the builders' convenience.
pub type TransferAction {
  Move
}

/// Redeemer of the third-party-logic withdraw-0 — the keeper-driven
/// graduation gate (§2 P3, §5). A keeper detects the settlement event and
/// submits a `SpendViaThirdParty` dispatch; nothing self-executes, the
/// predicate approves (§3.1). The negative mint itself is authorized by the
/// issuance logic (`Burn` mode, Q-GRAD-2), which runs in the same
/// transaction; retire-only instruments (`graduated_policy: None`) ride the
/// same path. Deliberately the only action in this first version: a
/// keeper-driven plain move is never approvable — extraction is admitted
/// only as part of graduation (Q-RULE-2). The typed redeemer leaves room to
/// add event-conditioned release/lockup actions back (§2 P2's transfer /
/// lockup flavors) without a format change.
pub type ThirdPartyAction {
  /// Event-conditioned burn of governed tokens — graduation or retirement.
  Graduate
}

/// Compile-time parameters of the issuance-logic validator. The issuance
/// credential is frozen at registration and gates the registry lifecycle, so
/// every stance here is designed in up front, not retrofitted (Q-GRAD-2).
pub type IssuanceParams {
  IssuanceParams {
    /// Policy of the core registry's node NFTs; used to locate this token's
    /// `RegistryNode` and resolve the governed policy id at runtime.
    registry_node_cs: PolicyId,
    /// Authority for minting and the registry lifecycle (single authority by
    /// design; `Burn` is deliberately exempt — settlement is event-gated,
    /// never an issuer lever, Q-GRAD-2).
    issuer: Credential,
    /// The pluggable P2 event-rule authority (§4, Q-RULE-1), also gating
    /// graduation — the same event condition the rules enforce. Chosen by
    /// the contract user when parameterizing (or forking) the final
    /// validator; the default wiring is a Credential satisfied by signature
    /// (key) or withdraw-0 (script, e.g. an oracle reading event facts via
    /// reference inputs).
    rule: Credential,
    /// Frozen at registration: transfer logic must remain this permissive
    /// script. Both `Register` and `UpdateNode` enforce it (Q-RULE-3).
    transfer_logic: ScriptHash,
    /// Frozen at registration: third-party logic must remain this
    /// governed-extraction script — keeper actions are admitted only through
    /// the event rule, never at the issuer's discretion (Q-RULE-2).
    third_party_logic: ScriptHash,
    /// P3 successor policy: `Some(p)` graduates 1:1 into `p`, `None` makes
    /// the instrument retire-only (§3.1, Q-GRAD-1).
    graduated_policy: Option<PolicyId>,
  }
}

/// Compile-time parameters of the third-party-logic validator. The token's
/// policy id derives from the issuance credential (the `issuance_mint`
/// template) before this validator compiles, so it is baked in — the cheapest
/// option per 09-DEVELOPING-SUBSTANDARDS.md, "Finding your own policy id".
pub type ThirdPartyParams {
  ThirdPartyParams {
    own_policy: PolicyId,
    /// The pluggable P2 event-rule authority (§4, Q-RULE-1) — the same
    /// credential the issuance logic's `Burn` mode is wired with.
    rule: Credential,
    /// P3 successor policy — **must mirror `IssuanceParams.graduated_policy`**
    /// (same source value): the two params live in separately compiled
    /// validators, so keeping them in sync is the deployer's convention, not
    /// an on-chain checkable fact. Used to pin keeper-driven graduation
    /// payouts back to the burned holders (Q-GRAD-2); `None` = retire-only,
    /// nothing to pin.
    graduated_policy: Option<PolicyId>,
  }
}

/// The core registry's node datum, projected to the fields the substandard
/// reads. Field order and arity MUST match the deployed core's `RegistryNode`
/// (09-DEVELOPING-SUBSTANDARDS.md) — verify at integration time. The node's
/// registry NFT asset name is `key`, the governed token's policy id.
pub type RegistryNode {
  RegistryNode {
    key: ByteArray,
    next: ByteArray,
    minting_logic_script: Credential,
    transfer_logic_script: Credential,
    third_party_logic_script: Credential,
    global_state_cs: ByteArray,
    protected_prefixes: List<ByteArray>,
  }
}
