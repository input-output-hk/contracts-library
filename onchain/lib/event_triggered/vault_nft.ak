//// Vault NFT policy (native mint) for the event-triggered assets substandard
//// (spec §3.1, I10).
////
//// Each vault is authenticated by exactly one NFT under this policy, minted
//// by the deployment's `authority` (the issuer in the reference deployment)
//// when the vault is created. Vault creation is out of scope; this policy is
//// the on-chain proof that a UTxO carrying its NFT is a genuine vault, which
//// the deposit and the vault validator require.
////
//// Only mints are admitted (exactly one unit of one name); burns are refused
//// so a vault can never lose its identity.

use aiken/collection/dict
use authorization.{is_authorized}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{Output, Transaction}
use event_triggered/types.{VaultNftParams}

pub fn validate(
  self: Transaction,
  own_policy: PolicyId,
  params: VaultNftParams,
) -> Bool {
  when dict.to_pairs(tokens(self.mint, own_policy)) is {
    [Pair(_, 1)] ->
      is_authorized(params.authority, self.extra_signatories, self.withdrawals)
    _ -> False
  }
}

/// The single vault NFT name under `nft_cs`, if the UTxO carries exactly one
/// unit of exactly one name. Shared by the deposit check (`issuance`) and the
/// vault validator: a UTxO at the vault address without this NFT is not a
/// vault.
pub fn nft_of(output: Output, nft_cs: PolicyId) -> Option<ByteArray> {
  when dict.to_pairs(tokens(output.value, nft_cs)) is {
    [Pair(name, 1)] -> Some(name)
    _ -> None
  }
}
