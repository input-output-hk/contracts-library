use aiken/collection/dict
use aiken/collection/list
use authorization.{is_authorized}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId, has_nft, tokens}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_input,
}
use smart_wallet/types.{WalletDatum}

/// Validate minting the wallet NFT, which identifies a valid smart wallet.
///
/// One-shot: the policy requires `seed_utxo` to be spent, so a single
/// policy id can mint at most once. Exactly one token with the expected
/// name is minted, and the continuation output at `out_ix` must sit at this
/// script's own address carrying that NFT with a fresh, empty `WalletDatum`.
/// The wallet's `admin` must authorize the mint.
pub fn validate_mint(
  seed_utxo: OutputReference,
  out_ix: Int,
  own_policy: PolicyId,
  wallet_token_name: AssetName,
  admin: Credential,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = self

  let correct_mint = {
    expect [Pair(minted_token_name, quantity)] = mint
      |> tokens(own_policy)
      |> dict.to_pairs()
    quantity == 1 && minted_token_name == wallet_token_name
  }

  // one-shot: the seed utxo can only be spent once
  expect Some(_) = find_input(inputs, seed_utxo)

  expect Some(wallet_output) = list.at(outputs, out_ix)

  expect  
      Output {
        address,
        value,
        datum: InlineDatum(datum),
        reference_script: None,
      }
    = wallet_output

  let correct_addr = address.payment_credential == Script(own_policy)

  let correct_value = has_nft(value, own_policy, wallet_token_name)

  let correct_datum = {
    expect WalletDatum { withdrawals } = datum
    withdrawals == []
  }

  and {
    is_authorized(admin, self.extra_signatories, self.withdrawals),
    correct_mint,
    correct_addr,
    correct_value,
    correct_datum,
  }
}

/// Validate burning the wallet NFT, permanently closing the wallet.
///
/// Requires exactly one token under the own policy to be burned. The burn only
/// matters alongside a `Close` spend, whose `validate_close` enforces the
/// `admin` authorization.
pub fn validate_burn(own_policy: PolicyId, self: Transaction) -> Bool {
  let Transaction { mint, .. } = self

  let correct_burn = {
    expect [Pair(_, quantity)] = mint
      |> tokens(own_policy)
      |> dict.to_pairs()
    quantity == -1
  }

  correct_burn
}
