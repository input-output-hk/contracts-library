//// On-chain types for the event-triggered assets CIP-113 substandard, the
//// tokenized bond instrument (issue #28). See
//// `docs/event-triggered-assets/spec.md` for the normative specification and
//// `docs/event-triggered-assets/design.typ` for the transaction figures.
////
//// The instrument ships four withdraw-zero validators — the substandard's
//// `issuance`, `transfer`, `third_party` and a smart-wallet
//// `transformation_script` — invoked by the CIP-113 core infrastructure: the
//// shared Programmable Logic Base custodies all token UTxOs and dispatches
//// spends to the transfer / third-party logic, the parameterized
//// `issuance_mint` policy invokes the minting logic on mint/burn, and the
//// registry mint/spend handlers carry the registration (§2). There is
//// deliberately no spend or mint endpoint of our own.
////
//// The schedule is **baked as validator constants** (§3.5): fixed 4% annual
//// over four years, precomputed off-chain in fixed-point `scale` units, with
//// `v4 ≈ 1.1699 × scale`. No on-chain compounding — the transformation script
//// looks the current value up by time and the graduation math reads the
//// baked `v4` (§4.4, §4.5). Because the constants must agree across the
//// validators that bake them, each deployment parameterizes every validator
//// from the same schedule (§4.4's transformation gate, §4.5's `d4` gate and
//// scaled mirror all derive from it).
////
//// Deployer-supplied constants (`own_policy`, asset names, authority
//// credentials, the schedule) are frozen at parameterization, before
//// registration. `own_policy` is the governed `cip_policy` — the hash of the
//// core `issuance_mint` template applied to this instrument's minting-logic
//// credential — computed off-chain and baked (09-DEVELOPING-SUBSTANDARDS,
//// "Finding your own policy id": the cheapest option).

use aiken/crypto.{ScriptHash}
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}

/// Mode redeemer on the minting-logic withdraw-0. The minting credential is
/// also the registration authority, so it runs in two contexts and must be
/// told why (09-DEVELOPING-SUBSTANDARDS.md, "Your issuance logic must know
/// why it is running"). Each mode is cross-checked against the transaction
/// shape in `issuance.validate` (§4.1, §4.5).
pub type MintingAction {
  /// Atomic register + first issue: validates registration authority (issuer
  /// signature), node shape and the first-batch mint in one transaction.
  RegisterAndMint
  /// Burn of the principal token: the deadline graduation (§4.5, Q-GRAD-2).
  Burn
}

/// Redeemer of the transfer-logic withdraw-0. P1 imposes no transfer rules —
/// the predicate approves every owner transfer (§4.2); the redeemer is typed
/// for the builders' convenience.
pub type TransferAction {
  Move
}

/// Redeemer of the third-party-logic withdraw-0 — the permissionless
/// graduation gate (§4.5). Anyone may submit; the predicate approves only
/// owner-authorized graduations (the burn's destination binding is enforced
/// by the minting logic's `Burn` mode, which runs in the same transaction).
pub type ThirdPartyAction {
  Graduate
}

/// Redeemer of the transformation-script withdraw-0 — the time gate of the
/// scheduled transformation (§4.4). Holder-passive and permissionless: no
/// signatures, anyone may submit.
pub type TransformationAction {
  Update
}

/// One step of the baked schedule (§3.5): at `deadline`, the value steps to
/// `value` (fixed-point `scale` units). `d1 < d2 < d3 < d4`, annual 4%.
pub type ScheduleStep {
  ScheduleStep { deadline: Int, value: Int }
}

/// `extra` of the CIP-68 reference datum (§3.3): the baked schedule, mirrored
/// for wallets and indexers, plus the currently recorded value (`v0 = scale`
/// at issue; stale values are harmless).
pub type BondExtra {
  BondExtra { schedule: List<ScheduleStep>, value: Int }
}

/// Inline datum of the reference token (CIP-68 `222`, §3.3). Heavy metadata
/// blobs would freeze the UTxO over the deployment's `max_inline_datum_bytes`
/// — keep it to the schedule and value.
pub type ReferenceDatum {
  ReferenceDatum { metadata: Data, version: Int, extra: BondExtra }
}

/// Inline datum of the principal token (§3.2): normally absent; after §4.3
/// optionally the owner's pre-committed payout payment credential. The only
/// writer is an owner-signed self-transfer (T2b), and the third-party
/// graduation path preserves it byte-for-byte — so a third party can complete
/// a graduation but never redirect the payout.
pub type PrincipalDatum {
  PrincipalDatum { payment_credential: Option<Credential> }
}

/// The core registry's node datum (§3.4), projected to the fields this
/// instrument reads. Field order and arity MUST match the deployed core's
/// `RegistryNode` (09-DEVELOPING-SUBSTANDARDS.md) — verify at integration
/// time. The node's registry NFT asset name is `key`, the governed policy id.
/// `unfracking_logic` and `global_state_cs` are unused by this instrument
/// (registered empty) and are frozen at registration, like the logic fields.
pub type RegistryNode {
  RegistryNode {
    key: ByteArray,
    next: ByteArray,
    minting_logic_script: Credential,
    transfer_logic_script: Credential,
    third_party_logic_script: Credential,
    unfracking_logic: Option<Credential>,
    global_state_cs: ByteArray,
  }
}

/// Compile-time parameters of the minting-logic validator (§4.1, §4.5).
pub type MintingParams {
  MintingParams {
    /// The governed policy id — hash of the core `issuance_mint` template
    /// applied to this credential. Every mode cross-checks against it.
    own_policy: PolicyId,
    /// Policy of the core registry's node NFTs; locates the instrument's
    /// `RegistryNode` and pins its shape at registration.
    registry_node_cs: PolicyId,
    /// Registration authority: the issuer signs the T0/T1 registration.
    issuer: Credential,
    /// Frozen at registration: the permissive transfer logic (Q-RULE-3) —
    /// `RegisterAndMint` pins the node's stance to it.
    transfer_logic: ScriptHash,
    /// Frozen at registration: the governed-extraction third-party logic
    /// (graduation-only in this instrument) — the node's stance is pinned
    /// to it, so the stance cannot be swapped out later.
    third_party_logic: ScriptHash,
    /// The smart-wallet stake credential that owns the reference token —
    /// registration pins the reference output's stake to it, so the
    /// transformation script's withdraw-0 is the only mutation authority
    /// over bond state (§4.4).
    transformation_script: ScriptHash,
    /// The principal asset name — the only name a graduation may burn.
    principal_name: AssetName,
    /// The CIP-68 reference asset name (a `222` label, §3.3).
    reference_name: AssetName,
    /// The graduated asset's policy (§4.5): minted exactly
    /// `burned × v4 / scale`, burn-backed ("no burn CIP, no mint", scaled).
    native_policy: PolicyId,
    /// The baked schedule `[(d1,v1) … (d4,v4)]` (§3.5). The registration
    /// cross-checks the reference datum against it; `v4` (the last step) and
    /// `d4` (the last deadline) drive the graduation gate and math.
    schedule: List<ScheduleStep>,
    /// The fixed-point scale of the schedule's values (`v0 = scale`).
    scale: Int,
  }
}

/// Compile-time parameters of the transfer-logic validator. `final_deadline`
/// is the baked `d4` (§3.5).
pub type TransferParams {
  TransferParams { own_policy: PolicyId, final_deadline: Int }
}

/// Compile-time parameters of the third-party-logic validator.
pub type ThirdPartyParams {
  ThirdPartyParams { own_policy: PolicyId, final_deadline: Int }
}

/// Compile-time parameters of the transformation-script validator. The
/// schedule is baked in — the T3 update is a pure lookup of these constants
/// (§4.4, I4).
pub type TransformationParams {
  TransformationParams {
    own_policy: PolicyId,
    reference_name: AssetName,
    schedule: List<ScheduleStep>,
  }
}

/// Compile-time parameters of the graduated asset's native mint policy
/// (§4.5): signer-agnostic and burn-backed. The deployer must pass the same
/// schedule and scale the other validators carry, so this policy derives the
/// identical `v4` the minting logic's Burn mode uses. The policy's own id is
/// supplied to the `mint` handler by the ledger — no baking needed.
pub type NativeMintParams {
  NativeMintParams {
    /// The bond's governed policy — the burn that backs the mint.
    cip_policy: PolicyId,
    /// The mirrored asset name: the native asset is minted under the same
    /// name the burn consumed, scaled by the schedule's final value.
    principal_name: AssetName,
    /// The fixed-point scale (`v4 ≈ 1.1699 × scale`, §3.5).
    scale: Int,
    /// The baked schedule — only its final step's value is read.
    schedule: List<ScheduleStep>,
  }
}
