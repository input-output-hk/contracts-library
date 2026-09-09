/// A configurable governance setting with a delayed-apply pattern.
///
/// `current` is the active value. `next` is a proposed new value
/// that, if present alongside `next_apply`, can be committed after
/// the specified time.
pub type SettingsDatum {
  current: Data,
  next: Option<Data>,
  next_apply: Option<Int>,
}

/// Redeemer for the spend endpoint of the settings validator.
pub type SpendRedeemer {
  Propose { out_ix: Int }
  Apply { out_ix: Int }
  Close
}

/// Redeemer for the mint endpoint of the settings validator.
pub type MintRedeemer {
  Mint { out_ix: Int }
  Burn
}
