use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, has_nft, quantity_of}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_input,
}
use dao/types.{StakePositionDatum}
use dao/utils.{nft_name_from_ref, single_minted}

/// Validate minting a stake position NFT (`CreatePosition`).
///
/// Mints exactly one NFT whose name is the hash of a consumed input (unique and
/// unforgeable), and requires the position output to sit at this script's own
/// address carrying that NFT and a fresh datum with no locks. Also deposits
/// at least one staked token into the position output.
pub fn validate_create_position(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  owner_utxo: OutputReference,
  own_policy: PolicyId,
  out_idx: Int,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = self

  let stake_nft_name = nft_name_from_ref(owner_utxo)

  let correct_mint = {
    let (minted_token_name, quantity) = single_minted(mint, own_policy)
    quantity == 1 && minted_token_name == stake_nft_name
  }

  expect Some(owner_input) = find_input(inputs, owner_utxo)

  expect Some(stake_position) = list.at(outputs, out_idx)

  // checks for stake position output
  expect  
      Output {
        address: stake_address,
        value: stake_value,
        datum: InlineDatum(stake_datum),
        reference_script: None,
      }
    = stake_position

  let correct_address = stake_address.payment_credential == Script(own_policy)

  // `flatten` yields one entry per asset plus lovelace (under the empty
  // policy), so exactly 3 entries means the position holds nothing but its
  // NFT, the staked token, and lovelace.
  let correct_value = has_nft(stake_value, own_policy, stake_nft_name) && quantity_of(
    stake_value,
    staked_token_policy,
    staked_token_name,
  ) >= 1 && list.length(assets.flatten(stake_value)) == 3

  let correct_datum = {
    expect StakePositionDatum { owner, delegatee, locks } = stake_datum
    and {
      owner == owner_input.output.address.payment_credential,
      delegatee == None,
      locks == [],
    }
  }

  and {
    correct_mint,
    correct_address,
    correct_value,
    correct_datum,
  }
}

/// Validate burning a stake position NFT (`CloseStakePosition`). The stake spend
/// validator (`ClosePosition`) enforces that all locks have expired and the
/// owner authorized; here we only require exactly one NFT to be burned.
pub fn validate_close_position(own_policy: PolicyId, self: Transaction) -> Bool {
  expect [Pair(_, quantity)] = self.mint
    |> assets.tokens(own_policy)
    |> dict.to_pairs()
  quantity == -1
}
