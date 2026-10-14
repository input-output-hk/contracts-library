//// On-chain types for the event-triggered assets CIP-113 substandard, the
//// tokenized bond instrument. See `docs/event-triggered-assets/spec.md` for
//// the normative specification and `docs/event-triggered-assets/design.typ`
//// for the transaction figures.
////
//// The instrument is registered once and then deposits are permissionless:
//// each deposit moves one unit's principal into a **chosen vault** and mints
//// one CIP-113 **certificate** at the Programmable Logic Base (PLB). The
//// certificate is the governed token; its asset name encodes the current step
//// (one byte) and its inline datum carries `{ start, commit, cnt_policy }`.
//// Over the bond's life a certificate claims scheduled **coupon** tokens
//// (`cNt`) — plain native assets under the coupon policy of the vault it
//// deposited into, whose asset name is the decimal lovelace amount they are
//// worth — and redeems them at that vault by burning (burn-to-pay). At
//// maturity the certificate claims a principal-only coupon and is retired.
//// Every advance or retirement **carries its coupon** (presence is enforced
//// on both the owner and the issuer paths).
////
//// The instrument ships four withdraw-zero validators — `issuance` (minting
//// logic and registration authority), `transfer` (name-monotone) and
//// `third_party` (the opt-in issuer trigger) — plus a `vault` spending
//// validator and a per-vault `coupon_policy` native mint policy. All are
//// exercised by the CIP-113 core infrastructure: the PLB custodies every
//// certificate UTxO and dispatches spends to the transfer / third-party
//// logic, the parameterized `issuance_mint` policy invokes the minting logic
//// on mint/burn, and the registry mint/spend handlers carry the registration.
//// There is deliberately no spend or mint endpoint of our own.
////
//// Deployer-supplied constants (the vault, the unit principal, authority
//// credentials) are frozen at parameterization, before registration. Note the
//// dependency order (09-DEVELOPING-MODULES, "Finding your own policy id"):
//// the governed policy id is the hash of the core `issuance_mint` template
//// applied to the minting-logic credential, so the issuance logic (and every
//// script whose hash feeds the issuance parameters) must not bake it — it
//// resolves the policy at runtime from the registry node. The coupon policy
//// and the vault are outside that dependency cone and may bake `cip_policy`.

use aiken/crypto.{ScriptHash}
use cardano/address.{Address, Credential}
use cardano/assets.{PolicyId}

/// Mode redeemer on the minting-logic withdraw-0. The minting credential is
/// also the registration authority, so it runs in four contexts and must be
/// told why (09-DEVELOPING-MODULES, "Your issuance logic must know why it is
/// running"). Each mode is cross-checked against the transaction shape in
/// `issuance.validate` (§4.1, §4.2, §4.5, §4.7).
pub type MintingAction {
  /// Register only (§4.1): inserts the instrument's RegistryNode. No
  /// certificate is minted, so the same registration serves every deposit.
  Register
  /// Permissionless unit deposit (§4.2): mints one step-`0` certificate when
  /// the chosen vault gains exactly the unit `principal`.
  Deposit
  /// Coupon claim (§4.5): burns the certificate's current name, mints the
  /// next and requires the step's coupon under the certificate's `cnt_policy`.
  Advance
  /// Certificate retirement (§4.7): burns the final name and requires the
  /// principal coupon under the certificate's `cnt_policy`.
  Retire
}

/// Redeemer of the transfer-logic withdraw-0. The name-monotone rule is
/// enforced structurally (§4.3); the redeemer is typed for the builders'
/// convenience.
pub type TransferAction {
  Move
}

/// One payout the redeemer names on a redemption (§4.6).
pub type Payout {
  Payout { address: Address, amount: Int }
}

/// Redeemer of the vault spend validator (§3.1, §4.2, §4.6).
pub type VaultAction {
  /// Unit deposit (§4.2): the vault gains exactly the baked `principal`.
  VaultDeposit
  /// Burn-to-pay redemption (§4.6): the vault loses exactly the sum decoded
  /// from the burned coupon names, paid to the named addresses.
  Redeem { payouts: List<Payout> }
}

/// Redeemer of the third-party-logic withdraw-0 — the opt-in issuer trigger
/// (§4.5, §4.7). Typed for the builders' convenience; the logic is structural.
pub type ThirdPartyAction {
  Trigger
}

/// Inline datum of a certificate (§3.3): the per-certificate claim state.
/// The step lives in the asset name; the coupon terms live in the coupon
/// policy selected by `cnt_policy`.
pub type CertificateDatum {
  CertificateDatum {
    /// Timeline origin: the validity upper bound at deposit.
    start: Int,
    /// The owner's committed payment credential for issuer-triggered claims.
    commit: Option<Credential>,
    /// The coupon policy of the vault this unit deposited into.
    cnt_policy: PolicyId,
  }
}

/// Inline datum of a vault (§3.1): binds the coupon policy whose negative
/// mints the `Redeem` path honors. The vault owner lives off-chain — custody
/// is the instrument's central assumption (§7), not a datum field.
pub type VaultDatum {
  VaultDatum { cnt_policy: PolicyId }
}

/// The core registry's node datum (§3.4), projected to the fields this
/// instrument reads. Field order and arity MUST match the deployed core's
/// `RegistryNode` (09-DEVELOPING-MODULES.md) — seven fields; the node's
/// registry NFT asset name is `key`, the governed policy id. An **empty
/// unfracking hook** is the `empty_vkey` convention: `VerificationKey(#"")`,
/// which forbids unfracking — the instrument's frozen posture.
pub type RegistryNode {
  RegistryNode {
    key: ByteArray,
    next: ByteArray,
    minting_logic_script: Credential,
    transfer_logic_script: Credential,
    third_party_logic_script: Credential,
    unfracking_logic_script: Credential,
    global_state_cs: ByteArray,
  }
}

/// Compile-time parameters of the minting-logic validator (§4.1, §4.2, §4.5,
/// §4.7). Deliberately NO policy id here: the governed policy id is a hash
/// *of* this script's applied form, so parameterizing it with the id would be
/// circular — the validator resolves it at runtime from the registry node
/// instead. The module is schedule-agnostic: coupon terms live in each vault's
/// coupon policy, and the certificate's `cnt_policy` selects them.
pub type MintingParams {
  MintingParams {
    /// Policy of the core registry's node NFTs; locates the instrument's
    /// `RegistryNode` and pins its shape.
    registry_node_cs: PolicyId,
    /// Registration authority: the issuer signs the registration and the
    /// issuer-triggered paths (§4.1, §4.5, §4.7).
    issuer: Credential,
    /// Frozen at registration: the name-monotone transfer logic — the node's
    /// stance is pinned to it.
    transfer_logic: ScriptHash,
    /// Frozen at registration: the issuer-triggered third-party logic — the
    /// node's stance is pinned to it.
    third_party_logic: ScriptHash,
    /// The vault script hash. The deposit mode locates the chosen vault UTxO
    /// by this payment credential and checks the pair's net ADA gain (I6).
    vault: ScriptHash,
    /// The unit principal, in lovelace. Each deposit must add exactly this to
    /// the chosen vault (I6).
    principal: Int,
  }
}

/// Compile-time parameters of the transfer-logic validator. The governed
/// policy id is resolved at runtime from the referenced registry node.
pub type TransferParams {
  TransferParams { registry_node_cs: PolicyId }
}

/// Compile-time parameters of the issuer-triggered third-party-logic validator.
pub type ThirdPartyParams {
  ThirdPartyParams { registry_node_cs: PolicyId, issuer: Credential }
}

/// Compile-time parameters of the vault validator (§3.1, §4.2, §4.6). The
/// coupon policy is read from the vault datum, so it is not a constant here.
pub type VaultParams {
  /// The unit principal a deposit must add to the vault (§4.2).
  VaultParams { principal: Int }
}

/// Compile-time parameters of one vault's coupon policy (§4.4, §4.5, §4.6,
/// §4.7). The policy is a plain native mint policy outside the issuance
/// dependency cone, so it bakes the governed `cip_policy` directly.
pub type CouponParams {
  CouponParams {
    /// The bond's governed policy — the certificate asset the claim anchor
    /// reads.
    cip_policy: PolicyId,
    /// The unit principal, in lovelace — the name of the graduation coupon.
    principal: Int,
    /// The constant number of lovelace-seconds between steps: step `k` opens
    /// at `start + k * interval`.
    interval: Int,
    /// The per-step coupon amounts; `length(amounts)` is the final step `N`.
    amounts: List<Int>,
  }
}
