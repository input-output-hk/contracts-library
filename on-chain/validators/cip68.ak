//// A reusable CIP-68 validator: a single script acting both as the minting
//// policy for a reference-NFT / user-token pair and as the spending validator
//// guarding the reference NFT (and its metadata datum).
////
//// Because mint and spend share one script, the policy id equals the payment
//// credential of the reference NFT's custody address — so the mint handler can
//// require the reference NFT to be locked at this very validator without an
//// extra address parameter.
////
//// The validator is parameterised by a `seed` output reference, making the
//// policy id one-shot and unique to a single issuance. Apply the parameter
//// off-chain to instantiate a CIP-68 policy per asset.
////
//// Authorisation model: metadata updates and burns are gated by *possession of
//// the paired user token* (it must be spent in the transaction). There is no
//// separate owner key — control of the token is control of the metadata.

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cip68/types.{Burn, BurnPair, Cip68Datum, MintAction, Mint, SpendAction,
  Update}
use cip68/validation

validator cip68(seed: OutputReference) {
  mint(redeemer: MintAction, policy_id: PolicyId, self: Transaction) {
    when redeemer is {
      Mint -> validation.mint_pair(self, policy_id, seed)
      Burn -> validation.burn(self, policy_id)
    }
  }

  spend(
    datum: Option<Cip68Datum>,
    redeemer: SpendAction,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    // The UTxO under custody must carry a well-formed CIP-68 datum.
    expect Some(_) = datum
    when redeemer is {
      Update -> validation.update(self, own_ref)
      BurnPair -> validation.burn_pair(self, own_ref)
    }
  }
}
