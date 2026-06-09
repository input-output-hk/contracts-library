//// CIP-67 asset-name label prefixes, as used by CIP-68.
////
//// Every CIP-68 asset name is built as a 4-byte CIP-67 label prefix
//// followed by an arbitrary "inner" name. The reference NFT and its paired
//// user token share the same inner name but carry different label prefixes.
////
//// The prefixes below are the fixed CIP-67 encodings (`0000 | label | crc8 | 0000`)
//// for the labels standardised by CIP-68, so they can be used as constants
//// rather than recomputed on-chain.

use aiken/primitive/bytearray

/// Byte length of a CIP-67 label prefix.
pub const label_length: Int = 4

/// `100` — reference NFT. Locks the metadata datum at a script address.
pub const reference_label: ByteArray = #"000643b0"

/// `222` — NFT user token (CIP-25-style metadata).
pub const nft_label: ByteArray = #"000de140"

/// `333` — fungible-token user token.
pub const ft_label: ByteArray = #"0014df10"

/// `444` — rich-fungible-token user token.
pub const rft_label: ByteArray = #"001bc280"

/// The 4-byte CIP-67 label prefix of an asset name.
pub fn label_of(asset_name: ByteArray) -> ByteArray {
  bytearray.take(asset_name, label_length)
}

/// The "inner" asset name, with the 4-byte CIP-67 label stripped off.
///
/// A reference NFT and its paired user token are related iff they share the
/// same inner name.
pub fn inner_name(asset_name: ByteArray) -> ByteArray {
  bytearray.drop(asset_name, label_length)
}

/// Is this asset name a reference NFT (label `100`)?
pub fn is_reference(asset_name: ByteArray) -> Bool {
  label_of(asset_name) == reference_label
}

/// Is this asset name one of the user-token labels (`222`, `333`, or `444`)?
pub fn is_user_token(asset_name: ByteArray) -> Bool {
  let label = label_of(asset_name)
  or {
    label == nft_label,
    label == ft_label,
    label == rft_label,
  }
}

/// Do a reference NFT and a user token form a CIP-68 pair? That is, the first
/// carries the `100` label, the second carries a user label, and both share the
/// same inner name.
pub fn is_pair(reference_name: ByteArray, user_name: ByteArray) -> Bool {
  and {
    is_reference(reference_name),
    is_user_token(user_name),
    inner_name(reference_name) == inner_name(user_name),
  }
}

test inner_name_strips_prefix() {
  inner_name(bytearray.concat(reference_label, "MyAsset")) == "MyAsset"
}

test pairing() {
  let reference = bytearray.concat(reference_label, "MyAsset")
  let user = bytearray.concat(nft_label, "MyAsset")
  is_pair(reference, user)
}

test non_pairing_inner_mismatch() {
  let reference = bytearray.concat(reference_label, "MyAsset")
  let user = bytearray.concat(nft_label, "Other")
  !is_pair(reference, user)
}

test non_pairing_both_user() {
  let user_a = bytearray.concat(nft_label, "MyAsset")
  let user_b = bytearray.concat(ft_label, "MyAsset")
  !is_pair(user_a, user_b)
}
