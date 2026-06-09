//// CIP-68 datum and redeemer types.

/// The CIP-68 metadata datum carried by the reference-NFT output.
///
/// On-chain it is encoded as `#6.121([ metadata, version, extra ])`, which is
/// exactly how this record serialises (constructor index `0`, three fields).
///
/// - `metadata`: the CIP-25-style metadata map (`bytes -> data`).
/// - `version`: the metadata-format version (`>= 1`).
/// - `extra`: arbitrary plutus data reserved for custom on-chain logic. Use
///   `Void`/unit when unused.
pub type Cip68Datum {
  metadata: Pairs<ByteArray, Data>,
  version: Int,
  extra: Data,
}

/// Redeemer for the CIP-68 minting policy.
pub type MintAction {
  /// Mint exactly one reference NFT (`100`) together with its paired user
  /// token (`222`/`333`/`444`).
  Mint
  /// Burn tokens of this policy (all minted quantities must be negative).
  Burn
}

/// Redeemer for the reference-NFT spending validator.
///
/// Both actions are authorised by *possession of the paired user token*: the
/// transaction must spend it as an input. No external key or script credential
/// is required — control of the token is control of the metadata.
pub type SpendAction {
  /// Update the metadata by continuing the reference NFT back to the script
  /// with a new (valid) datum.
  Update
  /// Burn the reference NFT together with its paired user token.
  BurnPair
}
