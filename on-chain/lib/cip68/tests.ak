//// Integration tests for the CIP-68 validation logic, exercising minting,
//// metadata updates, and burns against constructed transactions.

use aiken/primitive/bytearray
use cardano/address
use cardano/assets
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, OutputReference,
  Transaction}
use cip68/labels
use cip68/types.{Cip68Datum}
use cip68/validation

// ## Fixtures

const own_policy: assets.PolicyId =
  #"f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0"

const inner: ByteArray = "MyAsset"

const seed_ref: OutputReference =
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
    output_index: 0,
  }

const own_ref: OutputReference =
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 0,
  }

fn reference_name() -> ByteArray {
  bytearray.concat(labels.reference_label, inner)
}

fn user_name() -> ByteArray {
  bytearray.concat(labels.nft_label, inner)
}

fn datum() -> Cip68Datum {
  Cip68Datum { metadata: [], version: 1, extra: 0 }
}

/// A plain (non-script) input carrying an arbitrary value.
fn wallet_input(reference: OutputReference, value: assets.Value) -> Input {
  Input {
    output_reference: reference,
    output: Output {
      address: address.from_verification_key(
        #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      value,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// The script UTxO that custodies the reference NFT.
fn reference_input() -> Input {
  Input {
    output_reference: own_ref,
    output: Output {
      address: address.from_script(own_policy),
      value: assets.from_asset(own_policy, reference_name(), 1)
        |> assets.merge(assets.from_lovelace(2_000_000)),
      datum: InlineDatum(datum()),
      reference_script: None,
    },
  }
}

/// An output that re-locks the reference NFT at the script with a datum.
fn reference_output() -> Output {
  Output {
    address: address.from_script(own_policy),
    value: assets.from_asset(own_policy, reference_name(), 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: InlineDatum(datum()),
    reference_script: None,
  }
}

// ## Minting

test mint_pair_ok() {
  let mint =
    assets.from_asset(own_policy, reference_name(), 1)
      |> assets.merge(assets.from_asset(own_policy, user_name(), 1))
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [wallet_input(seed_ref, assets.from_lovelace(5_000_000))],
      mint: mint,
      outputs: [reference_output()],
    }
  validation.mint_pair(tx, own_policy, seed_ref)
}

// Fungible user tokens (label 333/quantity > 1) are accepted.
test mint_pair_fungible_ok() {
  let ft_user = bytearray.concat(labels.ft_label, inner)
  let mint =
    assets.from_asset(own_policy, reference_name(), 1)
      |> assets.merge(assets.from_asset(own_policy, ft_user, 1_000))
  let ref_out =
    Output { ..reference_output(), value: assets.from_asset(own_policy, reference_name(), 1) }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [wallet_input(seed_ref, assets.from_lovelace(5_000_000))],
      mint: mint,
      outputs: [ref_out],
    }
  validation.mint_pair(tx, own_policy, seed_ref)
}

// Without spending the seed UTxO the policy is not one-shot: must fail.
test mint_pair_without_seed() fail {
  let mint =
    assets.from_asset(own_policy, reference_name(), 1)
      |> assets.merge(assets.from_asset(own_policy, user_name(), 1))
  let other = OutputReference { ..seed_ref, output_index: 7 }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [wallet_input(other, assets.from_lovelace(5_000_000))],
      mint: mint,
      outputs: [reference_output()],
    }
  validation.mint_pair(tx, own_policy, seed_ref)
}

// Reference NFT not locked at the script => no custody => fails.
test mint_pair_reference_not_locked() {
  let mint =
    assets.from_asset(own_policy, reference_name(), 1)
      |> assets.merge(assets.from_asset(own_policy, user_name(), 1))
  let escaped =
    Output {
      ..reference_output(),
      address: address.from_verification_key(
        #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [wallet_input(seed_ref, assets.from_lovelace(5_000_000))],
      mint: mint,
      outputs: [escaped],
    }
  !validation.mint_pair(tx, own_policy, seed_ref)
}

// Mismatched inner names are not a valid pair => classify fails.
test mint_pair_mismatched_inner() fail {
  let bad_user = bytearray.concat(labels.nft_label, "Other")
  let mint =
    assets.from_asset(own_policy, reference_name(), 1)
      |> assets.merge(assets.from_asset(own_policy, bad_user, 1))
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [wallet_input(seed_ref, assets.from_lovelace(5_000_000))],
      mint: mint,
      outputs: [reference_output()],
    }
  validation.mint_pair(tx, own_policy, seed_ref)
}

test burn_all_negative_ok() {
  let mint =
    assets.from_asset(own_policy, reference_name(), -1)
      |> assets.merge(assets.from_asset(own_policy, user_name(), -1))
  let tx = Transaction { ..transaction.placeholder, mint: mint }
  validation.burn(tx, own_policy)
}

test burn_rejects_positive() {
  let mint = assets.from_asset(own_policy, user_name(), 5)
  let tx = Transaction { ..transaction.placeholder, mint: mint }
  !validation.burn(tx, own_policy)
}

// ## Updating

test update_ok() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      // reference UTxO + the user token being spent (authorisation)
      inputs: [
        reference_input(),
        wallet_input(seed_ref, assets.from_asset(own_policy, user_name(), 1)),
      ],
      outputs: [reference_output()],
    }
  validation.update(tx, own_ref)
}

// Updating without spending the paired user token is unauthorised.
test update_without_user_token() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [reference_input()],
      outputs: [reference_output()],
    }
  !validation.update(tx, own_ref)
}

// The reference NFT must continue to the script; sending it elsewhere fails.
test update_reference_escapes() {
  let escaped =
    Output {
      ..reference_output(),
      address: address.from_verification_key(
        #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        reference_input(),
        wallet_input(seed_ref, assets.from_asset(own_policy, user_name(), 1)),
      ],
      outputs: [escaped],
    }
  !validation.update(tx, own_ref)
}

// ## Burning the pair

test burn_pair_ok() {
  let mint =
    assets.from_asset(own_policy, reference_name(), -1)
      |> assets.merge(assets.from_asset(own_policy, user_name(), -1))
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [reference_input()],
      mint: mint,
    }
  validation.burn_pair(tx, own_ref)
}

// Burning the user token while keeping the reference NFT must fail.
test burn_pair_reference_survives() {
  let mint = assets.from_asset(own_policy, user_name(), -1)
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [reference_input()],
      mint: mint,
    }
  !validation.burn_pair(tx, own_ref)
}
