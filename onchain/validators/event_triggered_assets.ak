//// Reference module wiring for the event-triggered assets CIP-113
//// substandard — the tokenized bond.

use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{OutputReference, Transaction}
use event_triggered/coupon
use event_triggered/issuance as issuance_logic
use event_triggered/third_party as third_party_logic
use event_triggered/transfer as transfer_logic
use event_triggered/types.{
  CouponParams, MintingAction, MintingParams, ThirdPartyAction, ThirdPartyParams,
  TransferAction, TransferParams, VaultAction, VaultDatum, VaultParams,
}
use event_triggered/vault as vault_logic

/// Every withdraw-0 stake credential must be registered before it can appear
/// in a transaction's withdrawals, and after Conway registering a script
/// credential requires that script's consent (09-DEVELOPING-MODULES, "Your
/// credential must also carry a publish handler"). Each withdraw-0 validator
/// below accepts the registration certificate and refuses every other one.
fn accept_registration(redeemer: Certificate) -> Bool {
  when redeemer is {
    RegisterCredential { .. } -> True
    _ -> False
  }
}

/// Issuance logic (withdraw-0): the registration authority, the permissionless
/// unit deposit and the maturity retirement (see `issuance.validate`).
validator issuance(p: MintingParams) {
  withdraw(redeemer: MintingAction, account: Credential, self: Transaction) {
    issuance_logic.validate(redeemer, account, self, p)
  }

  publish(_redeemer: Data, certificate: Certificate, _self: Transaction) {
    accept_registration(certificate)
  }

  else(_) {
    fail
  }
}

/// Transfer logic (withdraw-0): step monotonicity — the claim state never
/// rewinds, and a certificate is only retired by its governed burn (§4.3,
/// §4.6).
validator transfer(p: TransferParams) {
  withdraw(_redeemer: TransferAction, account: Credential, self: Transaction) {
    transfer_logic.validate(account, self, p)
  }

  publish(_redeemer: Data, certificate: Certificate, _self: Transaction) {
    accept_registration(certificate)
  }

  else(_) {
    fail
  }
}

/// Third-party logic (withdraw-0): fail-closed — the instrument admits no
/// third-party extraction (§4.1).
validator third_party(p: ThirdPartyParams) {
  withdraw(_redeemer: ThirdPartyAction, account: Credential, self: Transaction) {
    third_party_logic.validate(account, self, p)
  }

  publish(_redeemer: Data, certificate: Certificate, _self: Transaction) {
    accept_registration(certificate)
  }

  else(_) {
    fail
  }
}

/// The vault spending validator (§3.1): a unit deposit gains exactly the baked
/// principal; a redemption pays out exactly the value of the burned coupons.
validator vault(p: VaultParams) {
  spend(
    datum: Option<VaultDatum>,
    redeemer: VaultAction,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    vault_logic.validate(redeemer, datum, own_ref, self, p)
  }

  else(_) {
    fail
  }
}

/// The coupon policy (§3.2): a plain native mint approving exactly the
/// scheduled step coupons and the maturity principal coupon, gated by the
/// transaction's validity range; negative quantities (redemption burns) are
/// always admitted. See `event_triggered/coupon.ak`.
validator coupon_policy(p: CouponParams) {
  mint(_redeemer: Data, own_policy: PolicyId, self: Transaction) {
    coupon.validate(self, own_policy, p)
  }

  else(_) {
    fail
  }
}
