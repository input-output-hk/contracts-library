use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Transaction}
use dao/types.{StakePositionDatum}
use dao/utils.{nft_name_from_ref}

/// Validate minting a stake position NFT (`CreatePosition`).
///
/// Mints exactly one NFT whose name is the hash of a consumed input (unique and
/// unforgeable), and requires the position output to sit at this script's own
/// address carrying that NFT and a fresh datum with no locks.
pub fn validate_create_position(own_policy: PolicyId, self: Transaction) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = self
  expect [Pair(name, 1)] =
    mint
      |> assets.tokens(own_policy)
      |> dict.to_pairs()
  let seeded =
    list.any(inputs, fn(i) { nft_name_from_ref(i.output_reference) == name })
  expect Some(position) =
    list.find(outputs, fn(o) { quantity_of(o.value, own_policy, name) == 1 })
  expect Script(hash) = position.address.payment_credential
  expect InlineDatum(d) = position.datum
  expect sd: StakePositionDatum = d
  and {
    seeded,
    hash == own_policy,
    sd.locks == [],
  }
}

/// Validate burning a stake position NFT (`CloseStakePosition`). The stake spend
/// validator (`ClosePosition`) enforces that all locks have expired and the
/// owner authorized; here we only require exactly one NFT to be burned.
pub fn validate_close_position(own_policy: PolicyId, self: Transaction) -> Bool {
  expect [Pair(_, quantity)] =
    self.mint
      |> assets.tokens(own_policy)
      |> dict.to_pairs()
  quantity == -1
}
