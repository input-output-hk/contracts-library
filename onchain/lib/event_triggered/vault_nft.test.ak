// Tests for the vault NFT policy (spec §3.1, I10).

use cardano/address.{VerificationKey}
use cardano/assets
use cardano/transaction.{Transaction, placeholder}
use event_triggered/types.{VaultNftParams}
use event_triggered/vault_nft

const vault_nft_cs = #"99999999999999999999999999999999999999999999999999999999"

const authority_key =
  #"55555555555555555555555555555555555555555555555555555555"

const vault_nft_name = "V0"

fn params() -> VaultNftParams {
  VaultNftParams { authority: VerificationKey(authority_key) }
}

fn check(mint: assets.Value, signers: List<ByteArray>) -> Bool {
  vault_nft.validate(
    Transaction { ..placeholder, mint, extra_signatories: signers },
    vault_nft_cs,
    params(),
  )
}

fn unit(qty: Int) -> assets.Value {
  assets.from_asset(vault_nft_cs, vault_nft_name, qty)
}

test mint_ok() {
  check(unit(1), [authority_key])
}

test rejects_without_authority() {
  !check(unit(1), [])
}

test rejects_wrong_quantity() {
  !check(unit(2), [authority_key])
}

test rejects_two_names() {
  !check(
    unit(1) |> assets.merge(assets.from_asset(vault_nft_cs, "V1", 1)),
    [authority_key],
  )
}

test rejects_burn() {
  !check(unit(-1), [authority_key])
}
