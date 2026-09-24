//// Reference substandard wiring for the event-triggered assets CIP-113
//// substandard — the tokenized bond.

use aiken/crypto.{ScriptHash}
use cardano/address.{Credential}
use cardano/transaction.{Transaction}
use event_triggered/issuance as issuance_logic
use event_triggered/native_mint
use event_triggered/third_party as third_party_logic
use event_triggered/transfer as transfer_logic
use event_triggered/transformation
use event_triggered/types.{
  MintingAction, MintingParams, NativeMintParams, ThirdPartyAction,
  ThirdPartyParams, TransferAction, TransferParams, TransformationAction,
  TransformationParams,
}

/// Issuance logic (withdraw-0): the atomic register + first issue and the
/// deadline graduation's burn (see `issuance_logic.validate`).
validator issuance(p: MintingParams) {
  withdraw(redeemer: MintingAction, account: Credential, self: Transaction) {
    issuance_logic.validate(redeemer, account, self, p)
  }

  else(_) {
    fail
  }
}

/// Transfer logic (withdraw-0): purely permissive — P1 imposes no transfer
/// rules (§4.2), at every point of the lifecycle.
validator transfer(p: TransferParams) {
  withdraw(_redeemer: TransferAction, _account: Credential, self: Transaction) {
    transfer_logic.validate(self, p)
  }

  else(_) {
    fail
  }
}

/// Third-party logic (withdraw-0): the permissionless graduation gate —
/// burn-shaped dispatches only, gated by the `d4` event gate; the burn's
/// destination binding is enforced by the issuance logic's `Burn` mode in the
/// same transaction (§4.5).
validator third_party(p: ThirdPartyParams) {
  withdraw(_redeemer: ThirdPartyAction, _account: Credential, self: Transaction) {
    third_party_logic.validate(self, p)
  }

  else(_) {
    fail
  }
}

/// The transformation script (withdraw-0): the smart-wallet stake credential
/// owning the reference token — its withdraw-0 authorizes the in-place
/// schedule update, holder-passively (§4.4).
validator transformation_script(p: TransformationParams) {
  withdraw(
    _redeemer: TransformationAction,
    account: Credential,
    self: Transaction,
  ) {
    transformation.validate(account, self, p)
  }

  else(_) {
    fail
  }
}

/// The graduated asset's native mint policy (§4.5): a plain minting policy
/// approving exactly `burned × v4 / scale`, burn-backed against the bond's
/// governed `cip_policy` ("no burn CIP, no mint", scaled), signer-agnostic.
/// See `event_triggered/native_mint.ak`.
validator native_mint_policy(p: NativeMintParams) {
  mint(_redeemer: Data, own_policy: ScriptHash, self: Transaction) {
    native_mint.validate(self, own_policy, p)
  }

  else(_) {
    fail
  }
}
